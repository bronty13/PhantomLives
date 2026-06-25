# Large synthetic samples (not committed)

This directory holds **large, generated** synthetic PII files used for
scalability / throughput testing of the redactor. The files themselves are
**git-ignored** (see `.gitignore` here — only this README and the ignore file
are tracked). Regenerate them on demand with the sample generator.

Everything produced is **synthetic and obviously fake** — the same generator
that produces the small committed fixtures in `../`. Credit-card numbers are
public Luhn-valid test numbers; routing numbers are real-format ABA-valid test
values. No real person's data is involved.

## Generate

From the `pii-redactor/` project root:

```sh
# one ~5 MB text file -> samples/large/large-5mb.txt
python3 scripts/generate-samples.py --large 5

# several sizes at once (MB) -> large-5mb.txt, large-50mb.txt, large-200mb.txt
python3 scripts/generate-samples.py --large 5 --large 50 --large 200

# vary the file shape
python3 scripts/generate-samples.py --large 20 --format csv   # -> large-20mb.csv
python3 scripts/generate-samples.py --large 10 --format log   # -> large-10mb.log

# by record count instead of size
python3 scripts/generate-samples.py --rows 100000             # -> large-100000rows.txt

# change the (otherwise fixed) seed
python3 scripts/generate-samples.py --large 5 --seed 42
```

Each generated record/row/line embeds the keyword-gated trigger words
(`Date of birth`/`DOB`, `routing`/`ABA`/`transit`, `Passport number`,
`Driver's license no`) so the gated detectors fire.

## Clean up

```sh
rm -f samples/large/large-*.txt samples/large/large-*.csv samples/large/large-*.log
```
