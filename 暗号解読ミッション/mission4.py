import math
import random
import time
import sys
import re

# --- 1. 多重 N-gram スコアテーブル ---
BIGRAM_SCORES = {
    "TH": -1.3, "HE": -1.4, "IN": -1.5, "ER": -1.5, "AN": -1.6,
    "RE": -1.6, "ND": -1.7, "ON": -1.7, "AT": -1.7, "EN": -1.8,
    "OU": -1.8, "HA": -1.8, "ED": -1.9, "TO": -1.9, "IT": -1.9,
    "AR": -2.0, "TE": -2.0, "OF": -2.0, "ST": -2.0, "OR": -2.1,
    "NT": -2.1, "NG": -2.1, "SE": -2.1, "VE": -2.1, "AS": -2.2,
    "HI": -2.2, "AL": -2.2, "RI": -2.2, "RO": -2.2, "CO": -2.2,
    "RA": -2.3, "LA": -2.3, "MA": -2.3, "TI": -2.3, "NO": -2.3,
    "IS": -2.0, "IM": -2.4, "PO": -2.3, "SS": -2.3, "BL": -2.3
}

TRIGRAM_SCORES = {
    "THE": -1.8, "AND": -2.0, "ING": -2.1, "HER": -2.2, "HAT": -2.2,
    "HIS": -2.3, "THA": -2.3, "ERE": -2.3, "FOR": -2.3, "ENT": -2.4,
    "ION": -2.4, "TER": -2.4, "WAS": -2.5, "YOU": -2.5, "ITH": -2.5,
    "VER": -2.5, "ALL": -2.5, "WIT": -2.5, "THI": -2.5, "TIO": -2.5,
    "NOT": -2.3, "POS": -2.5, "SIB": -2.5, "BLE": -2.3, "IMP": -2.6,
    "WOR": -2.6, "SEL": -2.6, "SAY": -2.5
}

QUADGRAM_SCORES = {
    "THAT": -2.3, "TION": -2.4, "WITH": -2.5, "HAVE": -2.6, "THIS": -2.7,
    "WILL": -2.8, "YOUR": -2.8, "FROM": -2.9, "THEM": -2.9, "KNOW": -3.0,
    "WANT": -3.0, "BEEN": -3.0, "GOOD": -3.1, "MUCH": -3.1, "SOME": -3.1,
    "TIME": -3.1, "VERY": -3.2, "WHEN": -3.2, "COME": -3.2, "HERE": -3.2,
    "JUST": -3.2, "LIKE": -3.2, "LONG": -3.3, "MAKE": -3.3, "MANY": -3.3,
    "MORE": -3.3, "ONLY": -3.3, "OVER": -3.3, "SUCH": -3.3, "TAKE": -3.3,
    "THAN": -3.3, "WELL": -3.3, "WERE": -3.3, "ATIO": -3.4, "EACH": -3.4,
    "HIGH": -3.4, "LAST": -3.4, "MIGHT": -3.4, "NEXT": -3.4, "READ": -3.4,
    "SAY": -3.4, "TELL": -3.4, "INGS": -3.5, "MENT": -3.5, "PRES": -3.5,
    "IGHT": -3.5, "OULD": -3.5, "ENCE": -3.6, "ANCE": -3.6, "THIN": -3.6,
    "THER": -3.6, "ONGR": -3.8, "NGRA": -3.8, "GRAT": -3.8, "RATU": -3.8,
    "ATUL": -3.8, "TULA": -3.8, "ULAT": -3.8, "LATI": -3.8, "CIPC": -3.9,
    "IPHE": -3.9, "PHER": -3.9, "MATH": -3.7, "SECR": -3.8, "ECRE": -3.8,
    "CRET": -3.8, "CESS": -3.5, "UCCE": -3.5, "OURA": -3.8, "RAGE": -3.8,
    "NOTH": -3.2, "OTHI": -3.2, "HING": -3.2, "IMPO": -3.2, "POSS": -3.0,
    "OSSI": -3.2, "SSIB": -3.2, "SIBL": -3.2, "IBLE": -3.0, "WORD": -3.0,
    "ITSE": -3.3, "TSEL": -3.3, "SELF": -3.1
}

# --- 2. 単語自動分割用の基本辞書 ---
ENGLISH_WORDS = {
    "A", "AM", "AN", "AND", "ARE", "AS", "AT", "BE", "BEAUTY", "BELIEVE",
    "BELONGS", "BUT", "BY", "CAN", "COURAGE", "CONTINUE", "DO", "DREAMS",
    "EVERY", "FAIL", "FAILURE", "FATAL", "FINAL", "FOR", "FUTURE", "GIVE",
    "GREAT", "HAS", "HAVE", "HE", "HER", "HIS", "HOW", "I", "IN", "IS", "IT",
    "ITS", "ITSELF", "JUST", "KNOW", "LIKE", "LOVE", "ME", "MORE", "MY",
    "NEVER", "NO", "NOT", "NOTHING", "OF", "ON", "ONE", "ONLY", "OR", "OUR",
    "POSSIBLE", "REALLY", "SAYS", "SO", "SOME", "SUCCESS", "THAT", "THE",
    "THEIR", "THEM", "THEY", "THIS", "THOSE", "TO", "UP", "WANT", "WAS",
    "WAY", "WE", "WHAT", "WHEN", "WHO", "WILL", "WITH", "WORD", "WORK",
    "WORLD", "YOU", "YOUR"
}

def decrypt_vigenere(ciphertext: str, key: str) -> str:
    decrypted = []
    key = key.upper()
    key_len = len(key)
    key_idx = 0
    for char in ciphertext:
        if char.isalpha():
            base = ord('A') if char.isupper() else ord('a')
            c_num = ord(char.upper()) - ord('A')
            k_num = ord(key[key_idx % key_len]) - ord('A')
            p_num = (c_num - k_num) % 26
            decrypted.append(chr(base + p_num))
            key_idx += 1
        else:
            decrypted.append(char)
    return "".join(decrypted)

def score_text(text: str) -> float:
    clean = [c.upper() for c in text if c.isalpha()]
    score = 0.0
    for i in range(len(clean) - 1):
        score += BIGRAM_SCORES.get("".join(clean[i:i+2]), -4.0)
    for i in range(len(clean) - 2):
        score += TRIGRAM_SCORES.get("".join(clean[i:i+3]), -5.5) * 1.2
    for i in range(len(clean) - 3):
        score += QUADGRAM_SCORES.get("".join(clean[i:i+4]), -7.0) * 1.5
    return score

def minimize_key(key: str) -> str:
    """繰り返しの鍵 (例: CYBERCYBER) を最小単位 (CYBER) に縮小正規化"""
    n = len(key)
    for i in range(1, n // 2 + 1):
        if n % i == 0:
            pattern = key[:i]
            if pattern * (n // i) == key:
                return pattern
    return key

def segment_text(text: str) -> str:
    """動的計画法 (DP) を使い、暗号テキストを綺麗な単語区切り英文へ変換"""
    clean_text = "".join(re.findall(r'[A-Za-z]', text)).upper()
    n = len(clean_text)
    if n == 0:
        return text
        
    dp = [(float('inf'), []) for _ in range(n + 1)]
    dp[0] = (0, [])
    
    for i in range(n):
        if dp[i][0] == float('inf'):
            continue
            
        for j in range(i + 1, min(i + 16, n + 1)):
            word = clean_text[i:j]
            cost = 1 if word in ENGLISH_WORDS else (10 + len(word))
            new_cost = dp[i][0] + cost
            
            if new_cost < dp[j][0]:
                dp[j] = (new_cost, dp[i][1] + [word])
                
    return " ".join(dp[n][1])

def solve_sa_for_length(ciphertext: str, key_len: int) -> tuple[str, float, str]:
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    current_key = [random.choice(alphabet) for _ in range(key_len)]
    current_score = score_text(decrypt_vigenere(ciphertext, "".join(current_key)))
    
    best_key = list(current_key)
    best_score = current_score
    
    temp = 20.0
    cooling_rate = 0.985
    min_temp = 0.01

    while temp > min_temp:
        for _ in range(40):
            neighbor = list(current_key)
            idx = random.randint(0, key_len - 1)
            neighbor[idx] = random.choice(alphabet)
            
            cand_key_str = "".join(neighbor)
            cand_score = score_text(decrypt_vigenere(ciphertext, cand_key_str))
            
            delta = cand_score - current_score
            if delta > 0 or random.random() < math.exp(delta / temp):
                current_key = neighbor
                current_score = cand_score
                
                if current_score > best_score:
                    best_key = list(current_key)
                    best_score = current_score
        temp *= cooling_rate
        
    final_key = "".join(best_key)
    return final_key, best_score, decrypt_vigenere(ciphertext, final_key)

def fully_auto_decrypt(ciphertext: str, max_key_len: int = 6, trials_per_len: int = 5) -> tuple[str, str, str, float, int]:
    print(f"\n1. 鍵長 1 〜 {max_key_len} （各{trials_per_len}回マルチリスタート）で高速解析中...")
    
    best_global_key = ""
    best_global_score = float('-inf')
    best_global_plain = ""
    best_global_klen = 0
    
    for klen in range(1, max_key_len + 1):
        best_klen_score = float('-inf')
        best_klen_key = ""
        best_klen_plain = ""
        
        for trial in range(trials_per_len):
            key, score, plain = solve_sa_for_length(ciphertext, klen)
            if score > best_klen_score:
                best_klen_score = score
                best_klen_key = key
                best_klen_plain = plain
                
        print(f"   - 鍵長 {klen:2d} : 推定鍵 = {best_klen_key:<8s} (Best Score: {best_klen_score:.2f})")
        
        if best_klen_score > best_global_score:
            best_global_score = best_klen_score
            best_global_key = best_klen_key
            best_global_plain = best_klen_plain
            best_global_klen = klen
            
    normalized_key = minimize_key(best_global_key)
    formatted_plain = segment_text(best_global_plain)
    
    return normalized_key, best_global_plain, formatted_plain, best_global_score, len(normalized_key)

def print_result(key: str, raw_plain: str, formatted_plain: str, score: float, klen: int, elapsed: float):
    print("\n" + "=" * 65)
    print(f"🎉 自動解読成功！ (処理時間: {elapsed:.3f} 秒)")
    print(f"🔑 決定された鍵長 : {klen}")
    print(f"🔑 特定された鍵   : {key}")
    print(f"📊 最終評価スコア : {score:.2f}")
    print("-" * 65)
    print(f"🔓 解読テキスト (Raw)   :\n{raw_plain}")
    print("-" * 65)
    print(f"📝 自動整形テキスト (Formatted) :\n{formatted_plain}")
    print("=" * 65)

# --- 標準入力インタフェース ---
if __name__ == "__main__":
    print("=" * 65)
    print("  🚀 完全自動ヴィジェネル暗号ソルバー (単一単語整形機能付き) 🚀")
    print("=" * 65)

    if not sys.stdin.isatty():
        ciphertext = sys.stdin.read().strip()
        if ciphertext:
            print(f"入力された暗号文:\n{ciphertext}\n")
            start_time = time.time()
            key, raw_plain, formatted_plain, score, klen = fully_auto_decrypt(ciphertext, max_key_len=6)
            elapsed = time.time() - start_time
            print_result(key, raw_plain, formatted_plain, score, klen, elapsed)
    else:
        while True:
            try:
                print("\n解読したい暗号文を入力（貼り付け）して Enter を押してください。")
                print("（※複数行の場合は最後に空行で Enter / 終了は Ctrl+C）\n")
                
                lines = []
                while True:
                    line = input("> ")
                    if not line and lines:
                        break
                    if line:
                        lines.append(line)
                
                ciphertext = "\n".join(lines).strip()
                if not ciphertext:
                    continue

                start_time = time.time()
                key, raw_plain, formatted_plain, score, klen = fully_auto_decrypt(ciphertext, max_key_len=6)
                elapsed = time.time() - start_time
                print_result(key, raw_plain, formatted_plain, score, klen, elapsed)

            except (KeyboardInterrupt, EOFError):
                print("\n\nプログラムを終了します。")
                break
