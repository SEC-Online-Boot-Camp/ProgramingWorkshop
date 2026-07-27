# Mission 4: Vigenere Cipher Solver
# Sample reference implementation for decoding Vigenere cipher with known key

CIPHER_TEXT = """
Mcz Qsvfor. Zxjoj Thib.
Wcn vkts ufyisg hrpsx qsnvxfc rcwoi, zim hrgg hbo gg wwpdsksxr.
Has ucm bg k uckr, xmh t bekpxf, cm qhixrwgu dfs esdrskg ggze byr vxzz wcn.
Zymy th dfs yfooixbmw htpvc. Wm wc yzfccr teod.
Cjxfi jsmhop wl vsbwgu lcvbbn kogm ngtysbcbm akqyl.
Typ hafoc vnbnpsw moyfl domdes myzesn rvbg dfs nblpstykzzx qsnvxf.
Lsh xjol o ecxe yxm vcoosc y famdfa bbcgrx hrc hxld,
ybw o wyqawxc qtb pgbw hryh kvirvf wx y ahaolh.
Wc xmh mfeqh t goafxh wchacn. Rfngd komvokomwmq wggdcow.
Oxb wy mys qtbxmh ufoyy mvo awivop, oly dfs aiwyb pvy fcerc rvx yow.
"""


def decode(text, key):
    """Decode Vigenere cipher text with given key"""
    key = key.upper()
    result = ""
    key_index = 0
    for ch in text:
        if ch.isalpha():
            base = ord("A") if ch.isupper() else ord("a")
            shift = ord(key[key_index % len(key)]) - ord("A")
            result += chr((ord(ch) - base - shift) % 26 + base)
            key_index += 1
        else:
            result += ch
    return result


# Hint: The key is "Tokyo" (Japanese capital, 5 characters in capital letters)
candidates = ["TOKYO"]

for key in candidates:
    print(f"key={key}:", decode(CIPHER_TEXT, key))
                
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
