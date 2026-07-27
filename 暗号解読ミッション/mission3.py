CIPHER = """
Zgh Ltektz!
Ziol ol zit ltektz zqla ygk ngx.
Zit stzztk t ol zit dglz yktjxtfz stzztk of Tfusoli.
Ltt zit ziktt vgkrl zit, ziol, qfr ziqz.
Tctkngft eqf lgsct ziol tqlosn vozi q sozzst ziofaofu.
Ngx qkt ctkn ldqkz qfr ngx eqf rg ziol egrt.
Zit jxoea wkgvf ygb pxdhl gctk zit sqmn rgu!
Uggr sxea qfr iqct yxf vozi ziol eohitk lnlztd!
"""

counts = {}
for ch in CIPHER.upper():
    if ch.isalpha():
        counts[ch] = counts.get(ch, 0) + 1

for letter, count in sorted(counts.items(), key=lambda item: -item[1]):
    print(f"{letter}: {count}")
