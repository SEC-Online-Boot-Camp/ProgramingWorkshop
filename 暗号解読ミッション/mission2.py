CIPHER = "DPTVZF OL EDFRT YZ DSTCPT HZ XLEP"


def decode(text, k):
    result = ""
    for ch in text:
        if ch.isalpha():
            base = ord("A") if ch.isupper() else ord("a")
            result += chr((ord(ch) - base - k) % 26 + base)
        else:
            result += ch
    return result


for k in range(5):
    print(f"k={k:2d}:", decode(CIPHER, k))
