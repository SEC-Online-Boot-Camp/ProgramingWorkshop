// トークン化の方法
export type TokenizerType = 'char' | 'simple' | 'particle' | 'intl' | 'tinyseg'

// 助詞・助動詞のリスト（よく使われるもの）
const PARTICLES = new Set([
  'は', 'が', 'を', 'に', 'へ', 'と', 'で', 'から', 'まで', 'より', 'の', 'や', 'か', 'も', 'ね', 'よ', 'な', 'だ', 'です', 'ます', 'た', 'て', 'ている', 'ました'
])

// メインのトークン化関数
export function tokenize(text: string, type: TokenizerType = 'particle'): string[] {
  switch(type){
    case 'char':
      return tokenizeChar(text)
    case 'simple':
      return tokenizeSimple(text)
    case 'particle':
      return tokenizeWithParticles(text)
    case 'intl':
      return tokenizeWithIntl(text)
    case 'tinyseg':
      return tokenizeWithTinySeg(text)
    default:
      return tokenizeWithParticles(text)
  }
}

// 1. 文字単位
function tokenizeChar(text: string): string[] {
  return text.split('').filter(c => c.trim().length > 0)
}

// 2. シンプル（日本語塊・英数字・記号）
function tokenizeSimple(text: string): string[] {
  const re = /[\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]+|[A-Za-z0-9]+|[、。！？,.!?]/g
  return text.match(re) || []
}

// 3. 助詞分割あり（改善版）
function tokenizeWithParticles(text: string): string[] {
  const re = /[\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]+|[A-Za-z0-9]+|[、。！？,.!?]/g
  const chunks = text.match(re) || []
  
  const result: string[] = []
  for(const chunk of chunks){
    if(/^[A-Za-z0-9、。！？,.!?]+$/.test(chunk)){
      result.push(chunk)
      continue
    }
    
    const tokens = splitByParticles(chunk)
    result.push(...tokens)
  }
  
  return result.filter(t => t.length > 0)
}

// 助詞による分割
function splitByParticles(text: string): string[] {
  if(text.length === 0) return []
  
  const result: string[] = []
  let current = ''
  let i = 0
  
  while(i < text.length){
    current += text[i]
    i++
    
    let foundParticle = false
    for(const p of PARTICLES){
      if(current.endsWith(p) && current.length > p.length){
        const before = current.slice(0, -p.length)
        if(before.length > 0) result.push(before)
        result.push(p)
        current = ''
        foundParticle = true
        break
      }
    }
    
    if(!foundParticle && current.length >= 8){
      result.push(current.slice(0, 4))
      current = current.slice(4)
    }
  }
  
  if(current.length > 0) result.push(current)
  return result
}

// 4. Intl.Segmenter（ブラウザネイティブ）
function tokenizeWithIntl(text: string): string[] {
  if(!('Intl' in globalThis && 'Segmenter' in Intl)){
    // フォールバック
    return tokenizeWithParticles(text)
  }
  
  try {
    const segmenter = new Intl.Segmenter('ja', { granularity: 'word' })
    const segments = segmenter.segment(text)
    return Array.from(segments)
      .filter(s => s.isWordLike || /[、。！？,.!?]/.test(s.segment))
      .map(s => s.segment)
  } catch(e){
    return tokenizeWithParticles(text)
  }
}



// 5. TinySegmenter（外部ライブラリ - 動的ロード）
let tinySegmenterInstance: any = null

export function loadTinySegmenter(): Promise<void> {
  if(tinySegmenterInstance) return Promise.resolve()
  
  return new Promise((resolve, reject) => {
    if(typeof window === 'undefined'){
      reject(new Error('TinySegmenter is only available in browser'))
      return
    }
    
    const script = document.createElement('script')
    script.src = 'http://chasen.org/~taku/software/TinySegmenter/tiny_segmenter-0.2.js'
    script.onload = () => {
      setTimeout(() => {
        if((window as any).TinySegmenter){
          try {
            tinySegmenterInstance = new (window as any).TinySegmenter()
            resolve()
          } catch(e){
            reject(new Error('TinySegmenter instantiation failed'))
          }
        } else {
          reject(new Error('TinySegmenter not found in window'))
        }
      }, 50)
    }
    script.onerror = () => reject(new Error('Failed to load TinySegmenter script'))
    document.head.appendChild(script)
  })
}

function tokenizeWithTinySeg(text: string): string[] {
  if(!tinySegmenterInstance){
    return tokenizeWithParticles(text)
  }
  
  try {
    const segments = tinySegmenterInstance.segment(text)
    return segments.filter((s: string) => s.trim().length > 0)
  } catch(e){
    return tokenizeWithParticles(text)
  }
}

// 後方互換性のため
export function simpleTokenize(text: string, mode: 'char'|'word'){
  return tokenize(text, mode === 'char' ? 'char' : 'particle')
}

export function ngrams(tokens: string[], n: number){
  if(n <= 0) return []
  const out: string[][] = []
  for(let i=0;i+n<=tokens.length;i++) out.push(tokens.slice(i,i+n))
  return out
}

export function countFreq<T extends string>(items: T[]){
  const m = new Map<T, number>()
  for(const it of items) m.set(it, (m.get(it)||0)+1)
  return m
}
