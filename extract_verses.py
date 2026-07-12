import pdfplumber
import json

MONTH_NUMS = {'August': 8, 'September': 9, 'October': 10, 'November': 11, 'December': 12}
COL_X = [57, 175, 293, 411, 529, 654, 769]  # Sun..Sat x-positions

result = {}

for month_name, month_num in MONTH_NUMS.items():
    pdf = pdfplumber.open(f'adds/verse/{month_name}.pdf')
    p = pdf.pages[0]
    words = p.extract_words(keep_blank_chars=True)

    # Group words by y-band (round to nearest 5)
    rows = {}
    for w in words:
        y = round(w['top'] / 5) * 5
        rows.setdefault(y, []).append(w)

    sorted_ys = sorted(rows.keys())

    # Find day-number rows (rows with >= 3 numeric tokens)
    for y in sorted_ys:
        ws = rows[y]
        nums = [w for w in ws if w['text'].strip().isdigit()]
        if len(nums) < 3:
            continue

        # Find the reading row within the next 65 units
        reading_words = []
        for ry in sorted_ys:
            if y < ry < y + 65:
                for w in rows[ry]:
                    t = w['text'].strip()
                    if not t.isdigit() and len(t) > 2 and t not in (
                        'Sunday', 'Monday', 'Tuesday', 'Wednesday',
                        'Thursday', 'Friday', 'Saturday'
                    ):
                        reading_words.append(w)

        for nw in nums:
            day = int(nw['text'].strip())
            if not (1 <= day <= 31):
                continue
            if not reading_words:
                continue
            closest = min(reading_words, key=lambda w: abs(w['x0'] - nw['x0']))
            if abs(closest['x0'] - nw['x0']) < 80:
                key = f'2026-{month_num:02d}-{day:02d}'
                result[key] = closest['text'].strip()

    pdf.close()
    count = sum(1 for k in result if f'-{month_num:02d}-' in k)
    print(f'{month_name}: {count} entries')

result = dict(sorted(result.items()))

with open('adds/verses.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)

print(f'Total: {len(result)} entries written to adds/verses.json')
