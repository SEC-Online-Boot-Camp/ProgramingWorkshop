'use client'
import { useEffect, useMemo, useState } from 'react'
import { tokenize, countFreq, ngrams, loadTinySegmenter, type TokenizerType } from './TokenUtils'

// ========================================
// 定数定義
// ========================================

// サンプルファイル設定
const SAMPLE_FILES: Record<string, string> = {
  news: '/samples/ニュース.txt',
  forum: '/samples/掲示板.txt',
  story: '/samples/昔話.txt',
  technical: '/samples/技術文.txt',
  constitution: '/samples/日本国憲法.txt'
}

const SAMPLE_LABELS: Record<string, string> = {
  news: 'ニュース',
  forum: '掲示板',
  story: '昔話',
  technical: '技術文',
  constitution: '日本国憲法'
}

// トークナイザー設定
const TOKENIZER_NAMES: Record<TokenizerType, string> = {
  char: '文字',
  simple: '句読点',
  particle: '助詞',
  intl: 'Intl.Segmenter',
  tinyseg: 'TinySegmenter',
}


// ========================================
// メインコンポーネント
// ========================================

export default function Home(){
  // ----------------------------------------
  // State: 入力・トークン化関連
  // ----------------------------------------
  const [text, setText] = useState('')
  const [tokenizerType, setTokenizerType] = useState<TokenizerType | ''>('')
  const [tokens, setTokens] = useState<string[]>([])
  const [bumped, setBumped] = useState(false)
  const [showHelp, setShowHelp] = useState(false)
  const [tinySegLoaded, setTinySegLoaded] = useState(false)
  const [loadingSample, setLoadingSample] = useState<string | null>(null)

  // ----------------------------------------
  // Effect: TinySegmenter動的ロード
  // ----------------------------------------
  useEffect(() => {
    if(tokenizerType === 'tinyseg' && !tinySegLoaded){
      loadTinySegmenter()
        .then(() => setTinySegLoaded(true))
        .catch(err => {
          console.error('TinySegmenter load failed:', err)
          alert('TinySegmenterの読み込みに失敗しました。他の方法を試してください。')
        })
    }
  }, [tokenizerType, tinySegLoaded])

  // ----------------------------------------
  // Effect: トークン化自動実行
  // ----------------------------------------
  useEffect(() => {
    if (text && tokenizerType && tokenizerType !== '') {
      const result = tokenize(text, tokenizerType as TokenizerType)
      setTokens(result)
      setBumped(true)
      setTimeout(() => setBumped(false), 260)
    } else {
      setTokens([])
    }
  }, [text, tokenizerType])

  // ----------------------------------------
  // State: Step2（N-gram頻度・確率）
  // ----------------------------------------
  const [ngramSize, setNgramSize] = useState<1 | 2 | 3 | 4 | 5 | ''>(1)
  const displayCount = 100

  // ----------------------------------------
  // State: Step3（予測入力）
  // ----------------------------------------
  const [predictInput, setPredictInput] = useState('')

  // ----------------------------------------
  // State: Step4（生成パラメータ）
  // ----------------------------------------
  const [generatedTokens, setGeneratedTokens] = useState<string[]>([])
  const [initialSeed, setInitialSeed] = useState<string[]>([])
  const [temperature, setTemperature] = useState(1.0)
  const [topK, setTopK] = useState(5)
  const [repetitionPenalty, setRepetitionPenalty] = useState(1.5)
  const [randomSeed, setRandomSeed] = useState('')
  const [showParameters, setShowParameters] = useState(true)
  const [updateStep3Input, setUpdateStep3Input] = useState(true)
  const [enableFallback, setEnableFallback] = useState(true)
  const [lastGeneratedToken, setLastGeneratedToken] = useState('')
  
  // ----------------------------------------
  // State: 生成履歴管理
  // ----------------------------------------
  const [generationHistory, setGenerationHistory] = useState<Array<{
    selectedToken: string
    originalProb: number
    adjustedProb: number
    allCandidates: Array<{token: string, originalProb: number, adjustedProb: number, isInTopK: boolean}>
    topKValue: number
    index: number
  }>>([])
  
  const [displayedGenerationDetail, setDisplayedGenerationDetail] = useState<{
    selectedToken: string
    originalProb: number
    adjustedProb: number
    allCandidates: Array<{token: string, originalProb: number, adjustedProb: number, isInTopK: boolean}>
    topKValue: number
    index: number
  } | null>(null)
  
  // ----------------------------------------
  // State: 履歴自動再生
  // ----------------------------------------
  const [isAutoPlaying, setIsAutoPlaying] = useState(false)
  const [autoPlaySpeed, setAutoPlaySpeed] = useState(500) // ミリ秒
  
  // ----------------------------------------
  // ユーティリティ: 擬似乱数生成器（LCG）
  // ----------------------------------------
  const seededRandom = (seed: number) => {
    let state = seed
    return () => {
      state = (state * 1664525 + 1013904223) % 4294967296
      return state / 4294967296
    }
  }
  
  // ----------------------------------------
  // Effect: 履歴自動再生
  // ----------------------------------------
  useEffect(() => {
    if (!isAutoPlaying || generationHistory.length === 0 || !displayedGenerationDetail) return
    
    const timer = setTimeout(() => {
      // 次の履歴項目へ
      const currentIdx = generationHistory.findIndex(h => h.index === displayedGenerationDetail.index)
      if (currentIdx > 0) {
        setDisplayedGenerationDetail(generationHistory[currentIdx - 1])
      } else {
        // 最後に到達したら自動再生を停止
        setIsAutoPlaying(false)
      }
    }, autoPlaySpeed)
    
    return () => clearTimeout(timer)
  }, [isAutoPlaying, displayedGenerationDetail, generationHistory, autoPlaySpeed])
  
  // ----------------------------------------
  // 関数: 履歴自動再生の開始
  // ----------------------------------------
  const startAutoPlay = () => {
    if (generationHistory.length === 0) return
    // 最初の履歴項目から開始
    setDisplayedGenerationDetail(generationHistory[generationHistory.length - 1])
    setIsAutoPlaying(true)
  }
  
  // ----------------------------------------
  // 関数: 「。」まで自動生成
  // ----------------------------------------
  const autoGenerateUntilPeriod = () => {
    if (predictions.length === 0 || ngramSize === '') return
    
    // 最初の1回目のみシードを保存
    if (generatedTokens.length === 0) {
      const seedTokens = predictInput.split(' ').filter(s => s.trim() !== '')
      setInitialSeed(seedTokens)
    }
    
    const MAX_ITERATIONS = 50
    let newTokens = [...generatedTokens]
    let newHistory = [...generationHistory]
    let currentPredictInput = predictInput
    
    for (let iteration = 0; iteration < MAX_ITERATIONS; iteration++) {
      // 現在のコンテキストに基づいて予測を再計算
      const inputParts = currentPredictInput.split(' ').filter(s => s.trim() !== '')
      const effectiveNgramSize = inputParts.length + 1
      
      let currentPredictions: [string, number, number][] = []
      
      if (inputParts.length === 0) {
        const total = tokenFreqs.reduce((sum, [_, count]) => sum + count, 0)
        currentPredictions = tokenFreqs.map(([token, count]) => [token, count, count / total] as [string, number, number])
      } else {
        const inputTokens = inputParts.flatMap(part => tokenize(part, tokenizerType as TokenizerType))
        if (inputTokens.length > 0) {
          let currentInputTokens = [...inputTokens]
          let currentNgramSize = effectiveNgramSize
          
          while (currentInputTokens.length > 0) {
            const targetNgrams = ngrams(tokens, currentNgramSize)
            const context = currentInputTokens.join(' ')
            
            const nextTokenCounts = new Map<string, number>()
            targetNgrams.forEach(gram => {
              const gramContext = gram.slice(0, -1).join(' ')
              if (gramContext === context) {
                const nextToken = gram[gram.length - 1]
                nextTokenCounts.set(nextToken, (nextTokenCounts.get(nextToken) || 0) + 1)
              }
            })
            
            const total = Array.from(nextTokenCounts.values()).reduce((a, b) => a + b, 0)
            if (total > 0) {
              currentPredictions = Array.from(nextTokenCounts.entries())
                .map(([token, count]) => [token, count, count / total] as [string, number, number])
                .sort((a, b) => b[1] - a[1])
              break
            }
            
            if (!enableFallback || currentInputTokens.length === 1) break
            currentInputTokens = currentInputTokens.slice(1)
            currentNgramSize = currentInputTokens.length + 1
          }
          
          if (currentPredictions.length === 0 && enableFallback) {
            const total = tokenFreqs.reduce((sum, [_, count]) => sum + count, 0)
            currentPredictions = tokenFreqs.map(([token, count]) => [token, count, count / total] as [string, number, number])
          }
        }
      }
      
      if (currentPredictions.length === 0) break
      
      let candidates = topK === 11 ? currentPredictions : currentPredictions.slice(0, topK)
      
      const penalizedProbs = candidates.map(([token, count, prob]) => {
        const occurrences = newTokens.filter(t => t === token).length
        const penalized = occurrences > 0 ? prob / Math.pow(repetitionPenalty, occurrences) : prob
        return [token, count, penalized] as [string, number, number]
      })
      
      const adjustedProbs = penalizedProbs.map(([token, count, prob]) => {
        const adjusted = Math.pow(prob, 1 / temperature)
        return [token, count, adjusted] as [string, number, number]
      })
      
      const totalProb = adjustedProbs.reduce((sum, [_, __, prob]) => sum + prob, 0)
      const normalizedProbs = adjustedProbs.map(([token, count, prob]) => 
        [token, count, prob / totalProb] as [string, number, number]
      )
      
      let rand: number
      if (randomSeed && randomSeed.trim() !== '') {
        const seedValue = parseInt(randomSeed) + newTokens.length
        const rng = seededRandom(seedValue)
        rand = rng()
      } else {
        rand = Math.random()
      }
      
      let cumulative = 0
      let nextToken = normalizedProbs[0][0]
      for (const [token, _, prob] of normalizedProbs) {
        cumulative += prob
        if (rand <= cumulative) {
          nextToken = token
          break
        }
      }
      
      const originalProbMap = new Map(currentPredictions.map(([t, _, p]) => [t, p]))
      const adjustedProbMap = new Map(normalizedProbs.map(([t, _, p]) => [t, p]))
      
      const newGenerationDetail = {
        selectedToken: nextToken,
        originalProb: originalProbMap.get(nextToken) || 0,
        adjustedProb: adjustedProbMap.get(nextToken) || 0,
        allCandidates: currentPredictions.map(([token, _, prob]) => ({
          token,
          originalProb: prob,
          adjustedProb: adjustedProbMap.get(token) || 0,
          isInTopK: topK === 11 || currentPredictions.findIndex(([t]) => t === token) < topK
        })),
        topKValue: topK,
        index: newTokens.length
      }
      
      newHistory = [newGenerationDetail, ...newHistory]
      newTokens.push(nextToken)
      
      if (updateStep3Input && ngramSize !== 1) {
        const contextSize = ngramSize - 1
        const currentInputs = currentPredictInput.split(' ').filter(s => s.trim() !== '')
        const newInputs = [...currentInputs, nextToken].slice(-contextSize)
        const paddedInputs = ['', '', '', ''].map((_, i) => {
          const index = i - (4 - newInputs.length)
          return index >= 0 ? newInputs[index] : ''
        })
        currentPredictInput = paddedInputs.join(' ')
      }
      
      // 「。」が生成されたら終了
      if (nextToken === '。') {
        break
      }
    }
    
    setGeneratedTokens(newTokens)
    setGenerationHistory(newHistory)
    setDisplayedGenerationDetail(newHistory[0] || null)
    setLastGeneratedToken(newTokens[newTokens.length - 1] || '')
    if (updateStep3Input) {
      setPredictInput(currentPredictInput)
    }
  }
  
  // ----------------------------------------
  // Memo: N-gram頻度計算
  // ----------------------------------------
  
  // 1-gram（トークン）頻度
  const tokenFreqs = useMemo(() => {
    const m = countFreq(tokens)
    return Array.from(m.entries()).sort((a,b) => b[1] - a[1])
  }, [tokens])
  
  // 2-gram（バイグラム）頻度
  const ngrams2 = useMemo(() => ngrams(tokens, 2), [tokens])
  const bigramFreqs = useMemo(() => {
    const m = countFreq(ngrams2.map(bg => bg.join(' ')))
    return Array.from(m.entries()).sort((a,b) => b[1] - a[1])
  }, [ngrams2])

  // 3-gram（トライグラム）頻度
  const ngrams3 = useMemo(() => ngrams(tokens, 3), [tokens])
  const trigramFreqs = useMemo(() => {
    const m = countFreq(ngrams3.map(tg => tg.join(' ')))
    return Array.from(m.entries()).sort((a,b) => b[1] - a[1])
  }, [ngrams3])

  // 4-gram頻度
  const ngrams4 = useMemo(() => ngrams(tokens, 4), [tokens])
  const tetragramFreqs = useMemo(() => {
    const m = countFreq(ngrams4.map(tg => tg.join(' ')))
    return Array.from(m.entries()).sort((a,b) => b[1] - a[1])
  }, [ngrams4])

  // 5-gram頻度
  const ngrams5 = useMemo(() => ngrams(tokens, 5), [tokens])
  const pentagramFreqs = useMemo(() => {
    const m = countFreq(ngrams5.map(tg => tg.join(' ')))
    return Array.from(m.entries()).sort((a,b) => b[1] - a[1])
  }, [ngrams5])

  // 現在選択中のN-gram頻度を取得
  const currentNgramFreqs = useMemo(() => {
    if (ngramSize === 1) return tokenFreqs
    if (ngramSize === 2) return bigramFreqs
    if (ngramSize === 3) return trigramFreqs
    if (ngramSize === 4) return tetragramFreqs
    if (ngramSize === 5) return pentagramFreqs
    return []
  }, [ngramSize, tokenFreqs, bigramFreqs, trigramFreqs, tetragramFreqs, pentagramFreqs])

  // ----------------------------------------
  // Memo: 条件付き確率計算（予測・生成用）
  // ----------------------------------------
  const predictions = useMemo(() => {
    if (tokens.length === 0) return []
    
    // 入力パース
    const inputParts = predictInput.split(' ').filter(s => s.trim() !== '')
    const effectiveNgramSize = inputParts.length + 1
    
    // 入力なし → 1-gram（全トークンの出現確率）
    if (inputParts.length === 0) {
      const total = tokenFreqs.reduce((sum, [_, count]) => sum + count, 0)
      return tokenFreqs.map(([token, count]) => [token, count, count / total] as [string, number, number])
    }

    // 入力をトークン化
    const inputTokens = inputParts.flatMap(part => tokenize(part, tokenizerType as TokenizerType))
    if (inputTokens.length === 0) return []

    // N-gramフォールバックループ
    let currentInputTokens = [...inputTokens]
    let currentNgramSize = effectiveNgramSize
    
    while (currentInputTokens.length > 0) {
      const targetNgrams = ngrams(tokens, currentNgramSize)
      const context = currentInputTokens.join(' ')
      
      // コンテキストに一致する次トークンをカウント
      const nextTokenCounts = new Map<string, number>()
      targetNgrams.forEach(gram => {
        const gramContext = gram.slice(0, -1).join(' ')
        if (gramContext === context) {
          const nextToken = gram[gram.length - 1]
          nextTokenCounts.set(nextToken, (nextTokenCounts.get(nextToken) || 0) + 1)
        }
      })

      // 確率計算
      const total = Array.from(nextTokenCounts.values()).reduce((a, b) => a + b, 0)
      if (total > 0) {
        return Array.from(nextTokenCounts.entries())
          .map(([token, count]) => [token, count, count / total] as [string, number, number])
          .sort((a, b) => b[1] - a[1])
      }
      
      // フォールバック: 先頭トークンを削除してN-gramサイズを減らす
      if (!enableFallback || currentInputTokens.length === 1) break
      currentInputTokens = currentInputTokens.slice(1)
      currentNgramSize = currentInputTokens.length + 1
    }
    
    // 最終フォールバック: 1-gram
    if (enableFallback) {
      const total = tokenFreqs.reduce((sum, [_, count]) => sum + count, 0)
      return tokenFreqs.map(([token, count]) => [token, count, count / total] as [string, number, number])
    }

    return []
  }, [predictInput, tokens, tokenizerType, tokenFreqs, enableFallback])

  // ----------------------------------------
  // 関数: サンプルファイル読み込み
  // ----------------------------------------
  async function applySample(k: string) {
    setLoadingSample(k)
    try {
      const response = await fetch(SAMPLE_FILES[k])
      if (response.ok) {
        const content = await response.text()
        setText(content)
        setTokenizerType('')
        // 生成・履歴・結果ブロックをクリア
        setGeneratedTokens([])
        setInitialSeed([])
        setGenerationHistory([])
        setDisplayedGenerationDetail(null)
        setLastGeneratedToken('')
        setPredictInput('')
      } else {
        alert('サンプルファイルの読み込みに失敗しました')
      }
    } catch (error) {
      console.error('Sample load error:', error)
      alert('サンプルファイルの読み込み中にエラーが発生しました')
    } finally {
      setLoadingSample(null)
    }
  }

  // ----------------------------------------
  // 関数: トークンコピー
  // ----------------------------------------

  // ========================================
  // JSX: レンダリング
  // ========================================
  
  return (
    <div className="h-screen flex flex-col bg-slate-900">
      {/* メインコンテンツ：横スクロール */}
      <div className="flex-1 overflow-x-auto overflow-y-hidden">
        <div className="inline-flex h-full gap-4 p-4">
          
          {/* ========== 入力ブロック ========== */}
          <div className="card-narrow">
            {/* タイトル */}
            <div className="mb-3">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <span>📝 入力</span>
              </h3>
              <p className="muted-xs mt-1">学習の元になる文章を入力する</p>
            </div>
            
            {/* 操作 */}
            <div className="mb-3 min-h-[44px] flex items-center">
              <div className="flex gap-2 flex-wrap">
                {Object.keys(SAMPLE_FILES).map(key => (
                  <button 
                    key={key}
                    onClick={() => applySample(key)} 
                    className="px-2 py-1 text-xs rounded bg-slate-700 hover:bg-slate-600 disabled:opacity-50"
                    disabled={loadingSample !== null}
                  >
                    {loadingSample === key ? '読み込み中...' : SAMPLE_LABELS[key]}
                  </button>
                ))}
              </div>
            </div>

            {/* 結果 */}
            <textarea 
              className="flex-1 w-full p-3 rounded bg-slate-900 border border-slate-700 resize-none text-sm" 
              value={text} 
              onChange={(e)=>setText(e.target.value)}
              // placeholder="ここに文章を入力..."
            />

            {/* その他 */}
            <div className="small-footer">
              <div className="text-xs text-slate-500">
                文字数: {text.length}
              </div>
              <button onClick={()=>{ setText('') }} className="px-2 py-1 text-xs rounded bg-red-600 hover:bg-red-700">クリア</button>
            </div>
          </div>

          {/* ========== 分割ブロック ========== */}
          <div className="card-narrow">
            {/* タイトル */}
            <div className="mb-3">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <span>✂️ 分割</span>
              </h3>
              <p className="muted-xs mt-1">文章をトークンに分割する</p>
            </div>

            {/* 操作 */}
            <div className="mb-3 min-h-[44px] flex items-center">
              <select 
                value={tokenizerType} 
                onChange={(e)=>setTokenizerType(e.target.value as TokenizerType | '')}
                className="w-full px-3 py-2 rounded bg-slate-700 text-slate-200 border border-slate-600 text-sm"
              >
                <option value="">-- 方法を選択してください --</option>
                {(Object.keys(TOKENIZER_NAMES) as TokenizerType[]).map(type => (
                  <option key={type} value={type}>{TOKENIZER_NAMES[type]}</option>
                ))}
              </select>
            </div>

            {/* 結果 */}
            <div className="flex-1 overflow-y-auto bg-slate-900 rounded border border-slate-700 p-3">
              {tokens.length === 0 ? (
                <div className="h-full flex items-center justify-center text-slate-500 text-sm">
                  {/* トークン化方法を選択してください */}
                </div>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {tokens.map((t, i)=> (
                    <div 
                      key={`${i}-${t}`} 
                      className={`token-chip ${bumped ? 'scale-105' : 'scale-100'}`}
                    >
                      {t}
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* その他 */}
            <div className="small-footer">
              <div className="muted-xs">
                {tokens.length > 0 ? `トークン数: ${tokens.length}` : '-'}
              </div>
            </div>
          </div>

          {/* ========== 分析ブロック ========== */}
          <div className="card-narrow">
            {/* タイトル */}
            <div className="mb-3">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <span>📊 分析</span>
              </h3>
              <p className="muted-xs mt-1">トークンの出現頻度と確率を分析する</p>
            </div>

            {/* 操作 */}
            <div className="mb-3 min-h-[44px] flex items-center gap-3">
              <label className="text-sm text-slate-300 whitespace-nowrap">N-gram:</label>
              <input 
                type="range" 
                min="1" 
                max="5" 
                value={ngramSize}
                onChange={(e) => setNgramSize(Number(e.target.value) as 1 | 2 | 3 | 4 | 5)}
                className="flex-1"
                disabled={tokens.length === 0}
              />
              <span className="text-sm font-bold text-blue-400 w-8 text-center">{ngramSize}</span>
            </div>

            {/* 結果 */}
            <div className="flex-1 overflow-y-auto bg-slate-900 rounded border border-slate-700 p-3">
              {tokens.length === 0 ? (
                <div className="h-full flex items-center justify-center text-slate-500 text-sm">
                  {/* トークン化を実行してください */}
                </div>
              ) : (
                <div className="space-y-1">
                  {currentNgramFreqs.slice(0, displayCount).map(([ngram, count], idx) => {
                    const total = currentNgramFreqs.reduce((sum, [_, c]) => sum + c, 0)
                    const probability = count / total
                    return (
                      <div 
                        key={idx} 
                        className="flex items-center gap-2 text-sm group cursor-default"
                        title={`出現回数: ${count}回 / 確率: ${(probability * 100).toFixed(1)}%`}
                      >
                        <div className="flex-[2] truncate font-mono text-xs">{ngram}</div>
                        <div className="w-24 h-5 bg-slate-800 rounded overflow-hidden relative">
                          <div 
                            className="h-full bg-gradient-to-r from-blue-500 to-purple-500 transition-all group-hover:from-blue-400 group-hover:to-purple-400"
                            style={{ width: `${probability * 100}%` }}
                          />
                        </div>
                        <div className="w-16 text-right flex-shrink-0">
                          <div className="text-purple-400 text-xs font-semibold">{(probability * 100).toFixed(1)}%</div>
                          <div className="text-slate-500 text-[10px] group-hover:text-slate-400">×{count}</div>
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>

            {/* その他 */}
            <div className="small-footer">
              <div className="muted-xs">
                {tokens.length > 0 ? `ユニーク${ngramSize}-gram数: ${currentNgramFreqs.length}（上位${Math.min(displayCount, currentNgramFreqs.length)}件表示）` : '-'}
              </div>
            </div>
          </div>

          {/* ========== 予測ブロック ========== */}
          <div className="card-narrow">
            {/* タイトル */}
            <div className="mb-3">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <span>🔮 予測</span>
              </h3>
              <p className="muted-xs mt-1">次に続くトークンを予測する</p>
            </div>
            {/* 操作 */}
            <div className="mb-3 min-h-[44px] flex flex-col gap-2">
              <div className="flex gap-1 flex-wrap">
                {[4, 3, 2, 1].map((offset, i) => (
                  <input 
                    key={i}
                    type="text"
                    value={predictInput.split(' ')[i] || ''}
                    onChange={(e) => {
                      const words = predictInput.split(' ')
                      words[i] = e.target.value
                      setPredictInput(words.slice(0, 4).join(' '))
                    }}
                    placeholder={`${offset}つ前`}
                    className="flex-1 min-w-[60px] px-2 py-2 rounded bg-slate-700 text-slate-200 border border-slate-600 text-sm"
                    disabled={tokens.length === 0}
                  />
                ))}
              </div>
            </div>

            {/* 結果 */}
            <div className="flex-1 overflow-y-auto bg-slate-900 rounded border border-slate-700 p-3">
              {tokens.length === 0 ? (
                <div className="h-full flex items-center justify-center text-slate-500 text-sm">
                  {/* トークン化を実行してください */}
                </div>
              ) : predictions.length === 0 ? (
                <div className="h-full flex items-center justify-center text-slate-500 text-sm">
                  一致するパターンが見つかりません
                </div>
              ) : (
                <div className="space-y-1">
                  {predictions.slice(0, 20).map(([token, count, prob], idx) => {
                    return (
                      <div 
                        key={idx} 
                        className="flex items-center gap-2 text-sm group cursor-default"
                        title={`出現回数: ${count}回 / 確率: ${(prob * 100).toFixed(1)}%`}
                      >
                        <div className="flex-[2] truncate font-mono text-xs">
                          {token}
                        </div>
                        <div className="w-24 h-5 bg-slate-800 rounded overflow-hidden relative">
                          <div 
                            className="h-full bg-gradient-to-r from-green-500 to-emerald-500 group-hover:from-green-400 group-hover:to-emerald-400 transition-all"
                            style={{ width: `${prob * 100}%` }}
                          />
                        </div>
                        <div className="w-16 text-right flex-shrink-0">
                          <div className="text-green-400 text-xs font-semibold">{(prob * 100).toFixed(1)}%</div>
                          <div className="text-slate-500 text-[10px] group-hover:text-slate-400">×{count}</div>
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>

            {/* その他 */}
            <div className="small-footer">
              <div className="muted-xs">
                {predictions.length > 0 ? `候補数: ${predictions.length}（上位${Math.min(20, predictions.length)}件表示）` : '-'}
              </div>
              <button 
                onClick={() => setPredictInput('')} 
                className="px-2 py-1 text-xs rounded bg-red-600 hover:bg-red-700"
                disabled={!predictInput.split(' ').some(s => s.trim() !== '')}
              >
                クリア
              </button>
            </div>
          </div>

          {/* ========== S生成ブロック ========== */}
          <div className="card-narrow">
            {/* タイトル */}
            <div className="mb-3">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <span>✨ 生成</span>
              </h3>
              <p className="muted-xs mt-1">パラメータに従って次のトークンを生成する</p>
            </div>

            {/* 操作 */}
            <div className="mb-3 flex gap-2">
              {/* パラメータ設定ボタン */}
              <button
                onClick={() => setShowParameters(!showParameters)}
                className="px-3 py-2 rounded bg-slate-700 hover:bg-slate-600 text-sm transition-colors flex items-center gap-2"
              >
                <span>⚙️</span>
                <span className="text-xs">{showParameters ? '▼' : '▶'}</span>
              </button>

              {/* 生成ボタン */}
              <button
                onClick={() => {
                  if (predictions.length === 0 || ngramSize === '') return
                  
                  // 最初の1回目のみシードを保存
                  if (generatedTokens.length === 0) {
                    const seedTokens = predictInput.split(' ').filter(s => s.trim() !== '')
                    setInitialSeed(seedTokens)
                  }
                  
                  // TemperatureとTop-Kを適用してトークンを選択
                  let nextToken: string
                  
                  // 1. Top-Kで候補を絞る（K=11の場合は制限なし）
                  let candidates = topK === 11 ? predictions : predictions.slice(0, topK)
                  
                  // 2. 繰り返しペナルティを適用
                  const penalizedProbs = candidates.map(([token, count, prob]) => {
                    // 生成済みトークンに含まれる回数をカウント
                    const occurrences = generatedTokens.filter(t => t === token).length
                    // ペナルティを適用（出現していれば確率を下げる）
                    const penalized = occurrences > 0 ? prob / Math.pow(repetitionPenalty, occurrences) : prob
                    return [token, count, penalized] as [string, number, number]
                  })
                  
                  // 3. Temperatureを適用して確率を調整
                  const adjustedProbs = penalizedProbs.map(([token, count, prob]) => {
                    const adjusted = Math.pow(prob, 1 / temperature)
                    return [token, count, adjusted] as [string, number, number]
                  })
                  
                  // 3. 正規化
                  const totalProb = adjustedProbs.reduce((sum, [_, __, prob]) => sum + prob, 0)
                  const normalizedProbs = adjustedProbs.map(([token, count, prob]) => 
                    [token, count, prob / totalProb] as [string, number, number]
                  )
                  
                  // 4. サンプリング
                  let rand: number
                  if (randomSeed && randomSeed.trim() !== '') {
                    // シード値が入力されている場合：固定乱数
                    const seedValue = parseInt(randomSeed) + generatedTokens.length
                    const rng = seededRandom(seedValue)
                    rand = rng()
                  } else {
                    // 空欄の場合：ランダム
                    rand = Math.random()
                  }
                  
                  let cumulative = 0
                  nextToken = normalizedProbs[0][0]
                  for (const [token, _, prob] of normalizedProbs) {
                    cumulative += prob
                    if (rand <= cumulative) {
                      nextToken = token
                      break
                    }
                  }
                  
                  // 生成詳細情報を記録
                  const originalProbMap = new Map(predictions.map(([t, _, p]) => [t, p]))
                  const adjustedProbMap = new Map(normalizedProbs.map(([t, _, p]) => [t, p]))
                  
                  const newGenerationDetail = {
                    selectedToken: nextToken,
                    originalProb: originalProbMap.get(nextToken) || 0,
                    adjustedProb: adjustedProbMap.get(nextToken) || 0,
                    allCandidates: predictions.map(([token, _, prob]) => ({
                      token,
                      originalProb: prob,
                      adjustedProb: adjustedProbMap.get(token) || 0,
                      isInTopK: topK === 11 || predictions.findIndex(([t]) => t === token) < topK
                    })),
                    topKValue: topK,
                    index: generatedTokens.length
                  }
                  
                  // 履歴の先頭に追加（新しいものが上）
                  setGenerationHistory([newGenerationDetail, ...generationHistory])
                  setDisplayedGenerationDetail(newGenerationDetail)
                  
                  setGeneratedTokens([...generatedTokens, nextToken])
                  setLastGeneratedToken(nextToken)
                  
                  // Step3の入力を更新（設定がONの場合のみ、かつ1-gram以外）
                  if (updateStep3Input && ngramSize !== 1) {
                    // Step2のN-gramサイズに応じて、必要な数のトークンを保持（N-gram - 1個）
                    const contextSize = ngramSize - 1
                    
                    // Step3の入力を更新（有効なトークンのみを扱う）
                    const currentInputs = predictInput.split(' ').filter(s => s.trim() !== '')
                    // 新しいトークンを追加し、contextSizeの数だけ保持
                    const newInputs = [...currentInputs, nextToken].slice(-contextSize)
                    
                    // 4つの枠に合わせて空文字で埋める（右詰め）
                    const paddedInputs = ['', '', '', ''].map((_, i) => {
                      const index = i - (4 - newInputs.length)
                      return index >= 0 ? newInputs[index] : ''
                    })
                    setPredictInput(paddedInputs.join(' '))
                  }
                }}
                disabled={tokens.length === 0 || predictions.length === 0 || ngramSize === ''}
                className="flex-1 px-4 py-2 bg-purple-600 hover:bg-purple-700 disabled:bg-slate-600 disabled:cursor-not-allowed rounded-lg font-medium transition-colors"
              >
                １語生成
              </button>

              {/* 「。」まで自動生成ボタン */}
              <button
                onClick={autoGenerateUntilPeriod}
                disabled={tokens.length === 0 || predictions.length === 0 || ngramSize === ''}
                className="flex-1 px-4 py-2 bg-pink-600 hover:bg-pink-700 disabled:bg-slate-600 disabled:cursor-not-allowed rounded-lg font-medium transition-colors"
              >
                １文生成
              </button>
            </div>

            {/* パラメータ群 */}
            {showParameters && (
              <div className="mb-3 px-1 py-3 bg-slate-800/50 rounded border border-slate-700">
                <div className="flex flex-col gap-3">
                  {/* N-gram */}
                  <div>
                    <label className="text-xs text-slate-400 mb-1 block flex items-center justify-between">
                      <span>N-gram: {ngramSize || '-'}</span>
                      <span className="text-[10px] text-slate-500">
                        {ngramSize === 1 ? '全体頻度' : ngramSize === 2 ? '直前1語' : ngramSize === 3 ? '直前2語' : ngramSize === 4 ? '直前3語' : ngramSize === 5 ? '直前4語' : '-'}
                      </span>
                    </label>
                    <input
                      type="range"
                      min="1"
                      max="5"
                      value={ngramSize || 1}
                      onChange={(e) => setNgramSize(Number(e.target.value) as 1 | 2 | 3 | 4 | 5)}
                      className="w-full"
                      disabled={tokens.length === 0}
                    />
                  </div>

                  {/* Temperature */}
                  <div>
                    <label className="text-xs text-slate-400 mb-1 block flex items-center justify-between">
                      <span>Temperature: {temperature.toFixed(1)}</span>
                      <span className="text-[10px] text-slate-500">
                        {temperature < 0.3 ? '決定的' : temperature < 0.7 ? 'やや決定的' : temperature < 1.3 ? 'バランス' : temperature < 1.7 ? 'ややランダム' : 'ランダム'}
                      </span>
                    </label>
                    <input
                      type="range"
                      min="0.1"
                      max="2.0"
                      step="0.1"
                      value={temperature}
                      onChange={(e) => setTemperature(Number(e.target.value))}
                      className="w-full"
                    />
                  </div>

                  {/* Top-K */}
                  <div>
                    <label className="text-xs text-slate-400 mb-1 block flex items-center justify-between">
                      <span>Top-K: {topK === 11 ? '制限なし' : topK}</span>
                      <span className="text-[10px] text-slate-500">
                        {topK === 11 ? '全候補' : `上位${topK}個`}
                      </span>
                    </label>
                    <input
                      type="range"
                      min="1"
                      max="11"
                      value={topK}
                      onChange={(e) => setTopK(Number(e.target.value))}
                      className="w-full"
                    />
                  </div>

                  {/* 繰り返しペナルティ */}
                  <div>
                    <label className="text-xs text-slate-400 mb-1 block flex items-center justify-between">
                      <span>繰り返しペナルティ: {repetitionPenalty.toFixed(1)}</span>
                      <span className="text-[10px] text-slate-500">
                        {repetitionPenalty === 1.0 ? 'なし' : repetitionPenalty < 1.3 ? '弱' : repetitionPenalty < 1.6 ? '中' : '強'}
                      </span>
                    </label>
                    <input
                      type="range"
                      min="1.0"
                      max="2.0"
                      step="0.1"
                      value={repetitionPenalty}
                      onChange={(e) => setRepetitionPenalty(Number(e.target.value))}
                      className="w-full"
                    />
                  </div>

                  {/* シード固定 */}
                  <div>
                    <label className="text-xs text-slate-400 mb-1 block">
                      シード値（空欄=ランダム、入力=固定）
                    </label>
                    <input
                      type="number"
                      placeholder="空欄でランダム、値を入力で固定（例: 42）"
                      value={randomSeed}
                      onChange={(e) => setRandomSeed(e.target.value)}
                      className="w-full px-3 py-2 rounded bg-slate-700 text-slate-200 border border-slate-600 text-sm"
                    />
                  </div>

                  {/* 予測ブロック自動更新 */}
                  <div>
                    <label className="text-xs text-slate-400 mb-1 block flex items-center justify-between">
                      <span>予測ブロックを自動更新する</span>
                      <span className="text-[10px] text-slate-500">
                        {updateStep3Input ? 'ON' : 'OFF'}
                      </span>
                    </label>
                    <div className="flex gap-2">
                      <button
                        onClick={() => setUpdateStep3Input(true)}
                        className={`btn-base ${
                          updateStep3Input 
                            ? 'bg-green-600 text-white' 
                            : 'bg-slate-700 text-slate-400 hover:bg-slate-600'
                        }`}
                      >
                        ON
                      </button>
                      <button
                        onClick={() => setUpdateStep3Input(false)}
                        className={`btn-base ${
                          !updateStep3Input 
                            ? 'bg-orange-600 text-white' 
                            : 'bg-slate-700 text-slate-400 hover:bg-slate-600'
                        }`}
                      >
                        OFF
                      </button>
                    </div>
                  </div>

                  {/* N-gramフォールバック */}
                  <div>
                    <label className="text-xs text-slate-400 mb-1 block flex items-center justify-between">
                      <span>N-gramフォールバック</span>
                      <span className="text-[10px] text-slate-500">
                        {enableFallback ? 'ON' : 'OFF'}
                      </span>
                    </label>
                    <div className="flex gap-2">
                      <button
                        onClick={() => setEnableFallback(true)}
                        className={`btn-base ${
                          enableFallback 
                            ? 'bg-green-600 text-white' 
                            : 'bg-slate-700 text-slate-400 hover:bg-slate-600'
                        }`}
                      >
                        ON
                      </button>
                      <button
                        onClick={() => setEnableFallback(false)}
                        className={`btn-base ${
                          !enableFallback 
                            ? 'bg-orange-600 text-white' 
                            : 'bg-slate-700 text-slate-400 hover:bg-slate-600'
                        }`}
                      >
                        OFF
                      </button>
                    </div>
                    <p className="text-[10px] text-slate-500 mt-1">
                      ONの場合、一致しない時N-gramを1つ減らして再試行
                    </p>
                  </div>
                </div>
              </div>
            )}

            {/* 結果 */}
            <div className="flex-1 overflow-y-auto bg-slate-900 rounded border border-slate-700 p-3">
              {/* 生成結果の可視化 */}
              {displayedGenerationDetail ? (
                <div>
                  {/* <div className="text-xs text-slate-400 mb-2">
                    {displayedGenerationDetail.index >= 0 && `#${initialSeed.length + displayedGenerationDetail.index} の生成結果`}
                  </div> */}
                  <div className="space-y-1">
                    {displayedGenerationDetail.allCandidates.map((candidate, idx) => {
                      const isSelected = candidate.token === displayedGenerationDetail.selectedToken
                      const isInTopK = candidate.isInTopK
                      return (
                        <div 
                          key={idx} 
                          className={`flex items-center gap-2 text-xs rounded px-2 py-1.5 transition-all ${
                            isInTopK ? 'bg-blue-900/20 border border-blue-700/30' : 'bg-slate-800/30 opacity-50'
                          } ${
                            isSelected ? 'ring-2 ring-purple-500 bg-purple-900/40' : ''
                          }`}
                        >
                          <div className="w-4 text-slate-500 text-[10px]">{idx + 1}</div>
                          <div className="flex-[2] truncate font-mono flex items-center gap-1">
                            {candidate.token}
                          </div>
                          <div className="flex-1 flex flex-col gap-0.5">
                            <div className="flex items-center gap-1">
                              <div className="w-16 h-2 bg-slate-800 rounded overflow-hidden">
                                <div 
                                  className="h-full bg-slate-500"
                                  style={{ width: `${candidate.originalProb * 100}%` }}
                                />
                              </div>
                              <div className="w-12 text-right text-[9px] text-slate-400">
                                {(candidate.originalProb * 100).toFixed(1)}%
                              </div>
                            </div>
                            {candidate.adjustedProb > 0 && (
                              <div className="flex items-center gap-1">
                                <div className="w-16 h-2 bg-slate-800 rounded overflow-hidden">
                                  <div 
                                    className={`h-full ${
                                      isSelected ? 'bg-purple-500' : 'bg-green-500'
                                    }`}
                                    style={{ width: `${candidate.adjustedProb * 100}%` }}
                                  />
                                </div>
                                <div className={`w-12 text-right text-[9px] font-semibold ${
                                  isSelected ? 'text-purple-400' : 'text-green-400'
                                }`}>
                                  {(candidate.adjustedProb * 100).toFixed(1)}%
                                </div>
                              </div>
                            )}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              ) : (
                <div className="text-slate-500 text-sm text-center py-8">
                  {/* トークンを生成すると、選択プロセスが可視化されます */}
                </div>
              )}
            </div>

            {/* その他 */}
            <div className="small-footer">
              <div className="text-xs text-slate-400">
              </div>
              <button
                onClick={() => {
                  setGeneratedTokens([])
                  setInitialSeed([])
                  setGenerationHistory([])
                  setDisplayedGenerationDetail(null)
                }}
                disabled={generatedTokens.length === 0}
                className="px-2 py-1 text-xs rounded bg-red-600 hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                クリア
              </button>
            </div>
          </div>

          {/* ========== 履歴ブロック ========== */}
          <div className="card-narrow">
            {/* タイトル */}
            <div className="mb-3">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <span>📜 履歴</span>
              </h3>
              <p className="muted-xs mt-1">生成されたトークンの履歴を表示する</p>
            </div>

            {/* 操作 */}
            <div className="mb-3 min-h-[44px] flex items-center justify-center gap-2">
              <button
                onClick={() => {
                  if (displayedGenerationDetail && displayedGenerationDetail.index > 0) {
                    setDisplayedGenerationDetail(generationHistory[generationHistory.length - 1])
                  }
                }}
                disabled={!displayedGenerationDetail || displayedGenerationDetail.index === 0}
                className="px-3 py-2 rounded bg-slate-700 hover:bg-slate-600 disabled:opacity-30 disabled:cursor-not-allowed text-sm transition-colors"
                title="最初へ"
              >
                «
              </button>
              <button
                onClick={() => {
                  if (displayedGenerationDetail && displayedGenerationDetail.index > 0) {
                    const currentIdx = generationHistory.findIndex(h => h.index === displayedGenerationDetail.index)
                    if (currentIdx < generationHistory.length - 1) {
                      setDisplayedGenerationDetail(generationHistory[currentIdx + 1])
                    }
                  }
                }}
                disabled={!displayedGenerationDetail || displayedGenerationDetail.index === 0}
                className="px-3 py-2 rounded bg-slate-700 hover:bg-slate-600 disabled:opacity-30 disabled:cursor-not-allowed text-sm transition-colors"
                title="前へ"
              >
                ‹
              </button>
              <button
                onClick={() => {
                  if (displayedGenerationDetail && displayedGenerationDetail.index < generationHistory.length - 1) {
                    const currentIdx = generationHistory.findIndex(h => h.index === displayedGenerationDetail.index)
                    if (currentIdx > 0) {
                      setDisplayedGenerationDetail(generationHistory[currentIdx - 1])
                    }
                  }
                }}
                disabled={!displayedGenerationDetail || displayedGenerationDetail.index === generationHistory.length - 1}
                className="px-3 py-2 rounded bg-slate-700 hover:bg-slate-600 disabled:opacity-30 disabled:cursor-not-allowed text-sm transition-colors"
                title="次へ"
              >
                ›
              </button>
              <button
                onClick={() => {
                  if (displayedGenerationDetail && displayedGenerationDetail.index < generationHistory.length - 1) {
                    setDisplayedGenerationDetail(generationHistory[0])
                  }
                }}
                disabled={!displayedGenerationDetail || displayedGenerationDetail.index === generationHistory.length - 1}
                className="px-3 py-2 rounded bg-slate-700 hover:bg-slate-600 disabled:opacity-30 disabled:cursor-not-allowed text-sm transition-colors"
                title="最後へ"
              >
                »
              </button>
              
              {/* 自動再生ボタン */}
              <button
                onClick={() => {
                  if (isAutoPlaying) {
                    setIsAutoPlaying(false)
                  } else {
                    startAutoPlay()
                  }
                }}
                disabled={generationHistory.length === 0}
                className="px-3 py-2 rounded bg-green-700 hover:bg-green-600 disabled:opacity-30 disabled:cursor-not-allowed text-sm transition-colors"
                title={isAutoPlaying ? "停止" : "自動再生"}
              >
                {isAutoPlaying ? '⏸' : '▶'}
              </button>
              
              {/* 再生速度スライダー */}
              <div className="flex items-center gap-1 ml-1">
                <input
                  type="range"
                  min="100"
                  max="2000"
                  step="100"
                  value={autoPlaySpeed}
                  onChange={(e) => setAutoPlaySpeed(Number(e.target.value))}
                  className="w-16"
                />
                <span className="text-[10px] text-slate-400 w-8">{(autoPlaySpeed / 1000).toFixed(1)}s</span>
              </div>
            </div>

            {/* 結果 */}
            <div className="flex-1 overflow-y-auto bg-slate-900 rounded border border-slate-700 p-3">
              {generatedTokens.length === 0 ? (
                <div className="h-full flex items-center justify-center text-slate-500 text-sm">
                  {/* トークンを生成すると履歴が表示されます */}
                </div>
              ) : (
                <div className="space-y-1">
                  {/* 生成されたトークン（逆順: 最新が上） */}
                  {[...generatedTokens].reverse().map((token, reverseIdx) => {
                    const actualIdx = generatedTokens.length - 1 - reverseIdx
                    // generationHistoryは最新が先頭なので、reverseIdxで取得
                    const historyItem = generationHistory[reverseIdx]
                    const isSelected = displayedGenerationDetail?.index === actualIdx
                    return (
                      <div 
                        key={initialSeed.length + actualIdx} 
                        className={`text-sm py-2 px-3 rounded cursor-pointer transition-all ${
                          isSelected
                            ? 'text-slate-100 bg-purple-900/40 border-2 border-purple-500'
                            : 'text-slate-200 bg-slate-800 border border-slate-600 hover:bg-slate-700 hover:border-slate-500'
                        }`}
                        onClick={() => historyItem && setDisplayedGenerationDetail(historyItem)}
                      >
                        <span className="text-xs text-slate-500 mr-2">{initialSeed.length + actualIdx}.</span>
                        <span className="font-mono">{token}</span>
                      </div>
                    )
                  })}
                  
                  {/* シードトークン（元の順序） */}
                  {initialSeed.map((token, idx) => (
                    <div key={idx} className="text-sm py-2 px-3 rounded text-slate-400 bg-slate-800/50 border border-slate-700">
                      <span className="text-xs text-slate-500 mr-2">{idx}.</span>
                      <span className="font-mono">{token}</span>
                      <span className="ml-2 text-xs text-slate-500">(シード)</span>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* その他 */}
            <div className="small-footer">
              <div className="text-xs text-slate-400">
                {generatedTokens.length > 0 ? (
                  <div>
                    <div>生成: {generatedTokens.length}トークン</div>
                  </div>
                ) : '-'}
              </div>
            </div>
          </div>

          {/* ========== 結果ブロック ========== */}
          <div className="card-narrow">
            {/* タイトル */}
            <div className="mb-3">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                <span>📄 結果</span>
              </h3>
              <p className="muted-xs mt-1">最終的な文章を表示する</p>
            </div>

            {/* 操作 */}
            <div className="mb-3 min-h-[44px] flex items-center gap-2">
              <button
                onClick={async () => {
                  const fullText = [...initialSeed, ...generatedTokens].join('')
                  try {
                    await navigator.clipboard.writeText(fullText)
                    alert('文章をクリップボードにコピーしました')
                  } catch (e) {
                    alert('コピーに失敗しました')
                  }
                }}
                disabled={generatedTokens.length === 0}
                className="flex-1 px-3 py-2 rounded bg-blue-600 hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm transition-colors"
              >
                📋 コピー
              </button>
            </div>

            {/* 結果 */}
            <div className="flex-1 overflow-y-auto bg-slate-900 rounded border border-slate-700 p-3">
              {generatedTokens.length === 0 ? (
                <div className="h-full flex items-center justify-center text-slate-500 text-sm">
                  {/* トークンを生成すると文章が表示されます */}
                </div>
              ) : (
                <div className="text-sm leading-relaxed">
                  {/* シードトークン */}
                  {initialSeed.map((token, idx) => (
                    <span 
                      key={`seed-${idx}`}
                      className="text-slate-400 font-mono"
                    >
                      {token}
                    </span>
                  ))}
                  {/* 生成されたトークン */}
                  {generatedTokens.map((token, idx) => (
                    <span 
                      key={`gen-${idx}`}
                      className="text-purple-300 font-mono"
                    >
                      {token}
                    </span>
                  ))}
                </div>
              )}
            </div>

            {/* その他 */}
            <div className="small-footer">
              <div className="text-xs text-slate-400">
                {generatedTokens.length > 0 ? (
                  <div>
                    {/* <div>総トークン数: {initialSeed.length + generatedTokens.length}</div> */}
                    {/* <div className="text-[10px] text-slate-500 mt-0.5">
                      シード: {initialSeed.length} / 生成: {generatedTokens.length}
                    </div> */}
                  </div>
                ) : '-'}
              </div>
            </div>
          </div>

        </div>
      </div>
    </div>
  )
}
