#!/usr/bin/env python3
"""Synthetic PII sample-data generator for the pii-redactor tool.

Dependency-free (stdlib only). Generates two things:

  1. With NO args: deterministically (re)writes the small representative
     sample files into ../samples/ next to this script. These are the
     committed fixtures used to exercise every detector, including the
     KEYWORD-GATED ones (DOB / routing / passport / driver's license),
     so the generated text always embeds the required trigger words.

  2. With --large / --rows: emits LARGE synthetic files into
     ../samples/large/ for scalability / throughput testing. Those are
     gitignored and not committed.

EVERYTHING produced here is SYNTHETIC and obviously fake. The credit-card
numbers are the well-known public test numbers (Visa 4111…, etc.) and the
ABA routing numbers are real-FORMAT valid bank routing numbers used as
public test values — neither is any real person's PII.

Examples
--------
    python3 scripts/generate-samples.py                 # regenerate small samples
    python3 scripts/generate-samples.py --large 5       # one ~5 MB txt file
    python3 scripts/generate-samples.py --large 5 --large 50 --large 200
    python3 scripts/generate-samples.py --large 20 --format csv
    python3 scripts/generate-samples.py --large 10 --format log
    python3 scripts/generate-samples.py --rows 100000   # by record count
    python3 scripts/generate-samples.py --seed 7        # different fixed seed
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLES_DIR = os.path.normpath(os.path.join(HERE, "..", "samples"))
LARGE_DIR = os.path.join(SAMPLES_DIR, "large")

# --------------------------------------------------------------------------
# Fake data pools (all synthetic)
# --------------------------------------------------------------------------

FIRST_NAMES = [
    "John", "Jane", "Michael", "Emily", "David", "Sarah", "Robert", "Linda",
    "James", "Patricia", "William", "Jennifer", "Richard", "Mary", "Joseph",
    "Karen", "Thomas", "Nancy", "Daniel", "Lisa", "Matthew", "Betty",
    "Anthony", "Sandra", "Mark", "Ashley", "Steven", "Kimberly", "Paul",
    "Donna", "Andrew", "Carol", "Joshua", "Michelle", "Kevin", "Amanda",
    "Brian", "Melissa", "George", "Deborah", "Priya", "Wei", "Carlos",
    "Fatima", "Diego", "Aisha", "Hiroshi", "Olga", "Samuel", "Grace",
]

LAST_NAMES = [
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller",
    "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez",
    "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
    "Lee", "Perez", "Thompson", "White", "Harris", "Sanchez", "Clark",
    "Ramirez", "Lewis", "Robinson", "Walker", "Young", "Allen", "King",
    "Wright", "Scott", "Torres", "Nguyen", "Hill", "Patel", "Khan",
    "Okafor", "Tanaka", "Petrov", "Rossi", "Cohen", "Murphy", "Reed",
]

TITLES = ["", "", "", "", "Dr.", "Mr.", "Ms.", "Mrs.", "Prof."]

# (city, state-abbr, zip)
CITIES = [
    ("Milwaukee", "WI", "53202"),
    ("Madison", "WI", "53703"),
    ("Buffalo", "NY", "14201"),
    ("Rochester", "NY", "14604"),
    ("Albany", "NY", "12207"),
    ("Chicago", "IL", "60601"),
    ("Springfield", "IL", "62701"),
    ("Columbus", "OH", "43215"),
    ("Cleveland", "OH", "44114"),
    ("Austin", "TX", "78701"),
    ("Dallas", "TX", "75201"),
    ("Houston", "TX", "77002"),
    ("Denver", "CO", "80202"),
    ("Boulder", "CO", "80302"),
    ("Phoenix", "AZ", "85003"),
    ("Tucson", "AZ", "85701"),
    ("Seattle", "WA", "98101"),
    ("Spokane", "WA", "99201"),
    ("Portland", "OR", "97204"),
    ("Boston", "MA", "02108"),
    ("Worcester", "MA", "01608"),
    ("Atlanta", "GA", "30303"),
    ("Savannah", "GA", "31401"),
    ("Miami", "FL", "33130"),
    ("Orlando", "FL", "32801"),
    ("Nashville", "TN", "37203"),
    ("Memphis", "TN", "38103"),
    ("Minneapolis", "MN", "55401"),
    ("Saint Paul", "MN", "55102"),
    ("Kansas City", "MO", "64106"),
]

STREET_NAMES = [
    "Main", "Oak", "Maple", "Cedar", "Elm", "Washington", "Lake", "Hill",
    "Park", "Sunset", "Lincoln", "Jefferson", "Madison", "Adams", "Franklin",
    "River", "Spring", "Highland", "Forest", "Meadow", "Birch", "Willow",
    "Cherry", "Walnut", "Chestnut", "Pine", "Ridge", "Valley", "Church",
    "Market",
]

STREET_TYPES = ["Street", "St", "Avenue", "Ave", "Road", "Rd", "Lane",
                "Ln", "Boulevard", "Blvd", "Drive", "Dr", "Court", "Ct",
                "Way", "Place", "Pl", "Terrace", "Trail"]

SECONDARY = ["", "", "", "Suite 401", "Apt 3B", "Unit 12", "Ste 220",
             "Apartment 7", "#15", "Floor 4"]

DOMAINS = ["example.com", "mail.example.net", "testmail.org", "sample.io",
           "demo-corp.example", "acme.example.com", "fakemail.example",
           "inbox.example.org", "mailbox.example.net", "webmail.example.io"]

# Public, well-known TEST credit-card numbers (Luhn-valid, not real cards).
TEST_CARDS = [
    "4111111111111111",   # Visa
    "5555555555554444",   # Mastercard
    "378282246310005",    # Amex
    "6011000990139424",   # Discover
    "4012888888881881",   # Visa
    "5105105105105100",   # Mastercard
]

# Real-FORMAT, ABA-checksum-valid routing numbers (public test/bank values).
TEST_ROUTING = ["021000021", "011401533", "111000025", "121000358",
                "026009593", "031176110"]

# Trigger words for the gated detectors, varied so prose stays realistic.
DOB_LABELS = ["Date of birth", "DOB", "D.O.B.", "Birth date", "born on"]
ROUTING_LABELS = ["Routing", "ABA", "RTN", "Routing/transit number"]


# --------------------------------------------------------------------------
# Field generators
# --------------------------------------------------------------------------

def luhn_complete(prefix_digits: str) -> str:
    """Return prefix_digits + a check digit so the whole string passes Luhn."""
    digits = [int(c) for c in prefix_digits]
    # Compute checksum as if a 0 check digit were appended, then fix it.
    total = 0
    # Position from the right of the final (prefix + check) number.
    # The check digit is position 1 (not doubled); work over the prefix.
    for i, d in enumerate(reversed(digits)):
        # i=0 here is the rightmost prefix digit, which becomes position 2
        # in the final number -> doubled.
        if i % 2 == 0:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    check = (10 - (total % 10)) % 10
    return prefix_digits + str(check)


def aba_valid(rng: random.Random) -> str:
    """Either reuse a known-valid routing number or build a fresh valid one."""
    if rng.random() < 0.5:
        return rng.choice(TEST_ROUTING)
    # Build 8 random digits, then solve the 9th so the ABA checksum holds:
    # 3*(d1+d4+d7) + 7*(d2+d5+d8) + 1*(d3+d6+d9) ≡ 0 (mod 10)
    d = [rng.randint(0, 9) for _ in range(8)]
    partial = (3 * (d[0] + d[3] + d[6])
               + 7 * (d[1] + d[4] + d[7])
               + 1 * (d[2] + d[5]))
    d9 = (10 - (partial % 10)) % 10
    return "".join(str(x) for x in d) + str(d9)


def make_card(rng: random.Random) -> str:
    """Mostly use canonical test cards; sometimes build a fresh Luhn-valid one."""
    if rng.random() < 0.7:
        return rng.choice(TEST_CARDS)
    prefix = "4" + "".join(str(rng.randint(0, 9)) for _ in range(14))
    return luhn_complete(prefix)


def fmt_card(rng: random.Random, number: str) -> str:
    """Format a 15/16-digit card with spaces or dashes or plain."""
    style = rng.choice(["plain", "space4", "dash4"])
    if style == "plain" or len(number) == 15:
        return number
    groups = [number[i:i + 4] for i in range(0, len(number), 4)]
    return ("-" if style == "dash4" else " ").join(groups)


def make_name(rng: random.Random, with_title: bool = True) -> str:
    title = rng.choice(TITLES) if with_title else ""
    name = f"{rng.choice(FIRST_NAMES)} {rng.choice(LAST_NAMES)}"
    return f"{title} {name}".strip()


def make_email(rng: random.Random, first: str, last: str) -> str:
    sep = rng.choice([".", "_", "", "."])
    num = rng.choice(["", "", str(rng.randint(1, 99))])
    return f"{first.lower()}{sep}{last.lower()}{num}@{rng.choice(DOMAINS)}"


def make_phone(rng: random.Random) -> str:
    area = rng.choice([716, 414, 312, 212, 303, 512, 617, 305, 206, 480])
    a, b = rng.randint(200, 999), rng.randint(1000, 9999)
    style = rng.choice(["paren", "dash", "dot", "intl"])
    if style == "paren":
        return f"({area}) {a}-{b}"
    if style == "dash":
        return f"{area}-{a}-{b}"
    if style == "dot":
        return f"{area}.{a}.{b}"
    return f"+1 {area}.{a}.{b}"


def make_ssn(rng: random.Random) -> str:
    # Avoid clearly-invalid 000/666/9xx area; still synthetic.
    area = rng.randint(100, 665)
    return f"{area:03d}-{rng.randint(10, 99)}-{rng.randint(1000, 9999)}"


def make_dob(rng: random.Random) -> str:
    style = rng.choice(["slash", "dash", "long"])
    y = rng.randint(1945, 2004)
    m = rng.randint(1, 12)
    d = rng.randint(1, 28)
    if style == "slash":
        return f"{m:02d}/{d:02d}/{y}"
    if style == "dash":
        return f"{y}-{m:02d}-{d:02d}"
    months = ["January", "February", "March", "April", "May", "June", "July",
              "August", "September", "October", "November", "December"]
    return f"{months[m - 1]} {d}, {y}"


def make_address(rng: random.Random):
    num = rng.randint(10, 9989)
    street = f"{num} {rng.choice(STREET_NAMES)} {rng.choice(STREET_TYPES)}"
    sec = rng.choice(SECONDARY)
    city, state, zc = rng.choice(CITIES)
    return street, sec, city, state, zc


VIN_CHARS = "ABCDEFGHJKLMNPRSTUVWXYZ0123456789"  # no I, O, Q


def make_vin(rng: random.Random) -> str:
    return "".join(rng.choice(VIN_CHARS) for _ in range(17))


def make_account(rng: random.Random) -> str:
    return "".join(str(rng.randint(0, 9)) for _ in range(rng.choice([10, 11, 12])))


def make_ipv4(rng: random.Random) -> str:
    nets = [(192, 168), (10, 0), (172, 16), (203, 0)]
    a, b = rng.choice(nets)
    return f"{a}.{b}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"


def make_ipv6(rng: random.Random) -> str:
    return "2001:db8:" + ":".join(f"{rng.randint(0, 0xffff):x}" for _ in range(6))


def make_passport(rng: random.Random) -> str:
    return rng.choice("ABCDEFGHJKLMNP") + "".join(
        str(rng.randint(0, 9)) for _ in range(7))


def make_dl(rng: random.Random) -> str:
    return rng.choice("DSTRMK") + "".join(
        str(rng.randint(0, 9)) for _ in range(7))


# --------------------------------------------------------------------------
# Record-oriented synthetic text (used by large-file generators)
# --------------------------------------------------------------------------

def synth_record_block(rng: random.Random, idx: int) -> str:
    """A multi-line synthetic record with a full PII mix incl. gated types."""
    first = rng.choice(FIRST_NAMES)
    last = rng.choice(LAST_NAMES)
    name = f"{rng.choice(TITLES)} {first} {last}".strip()
    street, sec, city, state, zc = make_address(rng)
    addr = street + (f", {sec}" if sec else "")
    dob_label = rng.choice(DOB_LABELS)
    rt_label = rng.choice(ROUTING_LABELS)
    lines = [
        f"===== Record #{idx} (SYNTHETIC) =====",
        f"Customer: {name}",
        f"Email: {make_email(rng, first, last)}",
        f"Phone: {make_phone(rng)}",
        f"SSN: {make_ssn(rng)}",
        f"{dob_label}: {make_dob(rng)}",
        f"Mailing address: {addr}, {city}, {state} {zc}",
        f"{rt_label} number: {aba_valid(rng)}",
        f"Account: {make_account(rng)}",
        f"Card on file: {fmt_card(rng, make_card(rng))}",
        f"Driver's license no {make_dl(rng)}",
        f"Passport number {make_passport(rng)}",
        f"Vehicle VIN: {make_vin(rng)}",
        f"Last login IP: {make_ipv4(rng)}",
        "",
    ]
    return "\n".join(lines)


CSV_HEADER = ("name,email,phone,ssn,dob,routing,account,card,"
              "drivers_license,passport,street,city,state,zip,vin,ip\n")


def synth_csv_row(rng: random.Random) -> str:
    first = rng.choice(FIRST_NAMES)
    last = rng.choice(LAST_NAMES)
    street, sec, city, state, zc = make_address(rng)
    street_full = street + (f" {sec}" if sec else "")
    fields = [
        f"{first} {last}",
        make_email(rng, first, last),
        make_phone(rng),
        make_ssn(rng),
        # Embed the DOB trigger right in the cell so the gated detector fires.
        f"DOB {make_dob(rng)}",
        f"routing {aba_valid(rng)}",
        make_account(rng),
        make_card(rng),
        f"DL {make_dl(rng)}",
        f"Passport {make_passport(rng)}",
        street_full,
        city,
        state,
        zc,
        make_vin(rng),
        make_ipv4(rng),
    ]
    # Quote any field containing a comma.
    out = []
    for f in fields:
        if "," in f:
            out.append('"' + f.replace('"', '""') + '"')
        else:
            out.append(f)
    return ",".join(out) + "\n"


def synth_log_line(rng: random.Random) -> str:
    y, mo, d = 2026, rng.randint(1, 6), rng.randint(1, 28)
    hh, mm, ss = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    ts = f"{y}-{mo:02d}-{d:02d} {hh:02d}:{mm:02d}:{ss:02d}"
    lvl = rng.choice(["INFO", "INFO", "INFO", "WARN", "ERROR", "DEBUG"])
    ip = make_ipv6(rng) if rng.random() < 0.12 else make_ipv4(rng)
    first = rng.choice(FIRST_NAMES)
    last = rng.choice(LAST_NAMES)
    kind = rng.random()
    if kind < 0.55:
        msg = f"request from {ip} path=/api/v1/customers status=200"
    elif kind < 0.75:
        msg = f"auth ok user={make_email(rng, first, last)} from {ip}"
    elif kind < 0.88:
        msg = (f"WARN leaked contact in payload phone={make_phone(rng)} "
               f"client={ip}")
    else:
        msg = (f"ERROR ssn appeared in log line ssn={make_ssn(rng)} "
               f"src={ip}")
    return f"{ts} [{lvl}] {msg}\n"


# --------------------------------------------------------------------------
# Small committed-fixture writers
# --------------------------------------------------------------------------

def write(path: str, content: str) -> int:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
    size = os.path.getsize(path)
    print(f"  wrote {os.path.relpath(path, SAMPLES_DIR)!s:42}  {size:>8,} bytes",
          file=sys.stderr)
    return size


def gen_loan_application() -> str:
    return """\
FIRST MERIDIAN MORTGAGE SERVICING
Loan Servicing & Origination Department
Confidential Borrower File  --  SYNTHETIC TEST DOCUMENT (no real persons)

Loan Number: 0098-44521-7
Property Type: Single-family residence

------------------------------------------------------------------
APPLICANT
------------------------------------------------------------------
Name:            Dr. Michael Anderson
Email:           michael.anderson@example.com
Home phone:      (716) 234-2242
Mobile:          716-555-8821
Social Security: 412-55-9087
Date of birth:   03/14/1981
Driver's license no D2289145 (issued NY)
Passport number A1234567

Mailing address: 482 Maple Avenue, Suite 401
                 Buffalo, NY 14201

------------------------------------------------------------------
CO-APPLICANT
------------------------------------------------------------------
Name:            Sarah Anderson
Email:           sarah_anderson17@testmail.org
Phone:           +1 716.555.3390
Social Security: 388-21-4410
D.O.B.:          July 9, 1983
Driver's license no D5510928

------------------------------------------------------------------
BANKING & PAYMENT
------------------------------------------------------------------
Bank:            Lakeshore Community Credit Union
ABA routing number: 021000021
Account number:  100044829017
Backup routing/transit number: 011401533

Autopay card on file (Visa):   4111 1111 1111 1111
Secondary card (Mastercard):   5555-5555-5555-4444

------------------------------------------------------------------
NOTES
------------------------------------------------------------------
Underwriter Jane Williams (ext. 312-555-0142) verified income on file.
Co-applicant born on August 22, 1984 per secondary ID review.
Escrow analyst Robert Lee reachable at robert.lee9@sample.io.
All figures and identities above are fabricated for QA purposes only.
"""


def gen_customers_csv() -> str:
    return """\
name,email,phone,ssn,dob,city,state,zip,account
Emily Carter,emily.carter@example.com,(414) 555-0198,501-22-7788,DOB 06/12/1990,Milwaukee,WI,53202,100299481
James Patel,james.patel3@sample.io,312-555-7741,233-41-9920,DOB 1985-11-03,Chicago,IL,60601,100488213
Linda Nguyen,linda_nguyen@testmail.org,+1 212.555.6610,455-09-3321,DOB April 2 1979,Buffalo,NY,14201,100571902
Carlos Ramirez,carlos.ramirez@mail.example.net,303-555-2204,612-33-7781,DOB 09/30/1992,Denver,CO,80202,100633870
Aisha Khan,aisha.khan21@example.com,(512) 555-9043,377-88-1190,DOB 1988-02-17,Austin,TX,78701,100702255
David Brown,david.brown@fakemail.example,617-555-3398,290-44-6612,DOB July 8 1975,Boston,MA,02108,100744019
Grace Okafor,grace.okafor@inbox.example.org,(305) 555-7720,531-21-9087,DOB 12/01/1995,Miami,FL,33130,100819644
Hiroshi Tanaka,hiroshi.tanaka@demo-corp.example,206-555-4412,148-90-3322,DOB 1982-05-25,Seattle,WA,98101,100888301
"""


def gen_contacts_json() -> str:
    data = [
        {
            "id": 1,
            "name": "Jennifer Thompson",
            "email": "jennifer.thompson@example.com",
            "phone": "(716) 555-1020",
            "ssn": "402-19-8833",
            "dateOfBirth": "1986-03-22",
            "address": {
                "street": "73 Oak Street, Apt 3B",
                "city": "Rochester", "state": "NY", "zip": "14604",
            },
            "banking": {"routingNumber": "021000021", "account": "100459872013"},
            "card": "378282246310005",
            "ip": "192.168.1.42",
        },
        {
            "id": 2,
            "name": "Dr. Wei Chen",
            "email": "wei.chen@sample.io",
            "phone": "312-555-7788",
            "ssn": "319-55-4471",
            "dob": "born November 4, 1979",
            "address": {
                "street": "1200 Lincoln Boulevard",
                "city": "Chicago", "state": "IL", "zip": "60601",
            },
            "banking": {"ABA": "011401533", "account": "100783345021"},
            "card": "6011000990139424",
            "ip": "10.0.0.7",
        },
        {
            "id": 3,
            "name": "Olga Petrov",
            "email": "olga.petrov88@testmail.org",
            "phone": "+1 303.555.4419",
            "ssn": "566-21-0098",
            "dob": "D.O.B. 1991-07-15",
            "address": {
                "street": "55 Cedar Lane, Unit 12",
                "city": "Denver", "state": "CO", "zip": "80202",
            },
            "card": "5105105105105100",
            "ip": "172.16.5.88",
            "passport": "Passport number C7781230",
        },
        {
            "id": 4,
            "name": "Samuel Reed",
            "email": "samuel.reed@mail.example.net",
            "phone": "(512) 555-3367",
            "ssn": "271-44-6650",
            "dateOfBirth": "DOB 04/18/1973",
            "address": {
                "street": "910 River Road",
                "city": "Austin", "state": "TX", "zip": "78701",
            },
            "banking": {"routing": "111000025", "account": "100920018744"},
            "driversLicense": "Driver's license no D4419087",
            "ip": "192.168.10.5",
        },
        {
            "id": 5,
            "name": "Priya Sharma",
            "email": "priya.sharma@inbox.example.org",
            "phone": "206-555-9921",
            "ssn": "488-33-1276",
            "dob": "birth date 1994-12-09",
            "address": {
                "street": "318 Highland Drive, Ste 220",
                "city": "Seattle", "state": "WA", "zip": "98101",
            },
            "card": "4012888888881881",
            "ip": "2001:db8:85a3::8a2e:370:7334",
        },
        {
            "id": 6,
            "name": "George Murphy",
            "email": "george.murphy42@fakemail.example",
            "phone": "(617) 555-7700",
            "ssn": "350-12-4498",
            "dob": "Date of birth: February 28, 1968",
            "address": {
                "street": "27 Church Street",
                "city": "Boston", "state": "MA", "zip": "02108",
            },
            "banking": {"transit": "121000358", "account": "100110293355"},
            "card": "5555555555554444",
            "vin": "1HGBH41JXMN109186",
            "ip": "10.10.10.10",
        },
    ]
    return json.dumps(data, indent=2) + "\n"


def gen_server_log() -> str:
    return """\
2026-01-04 08:12:33 [INFO] startup: api server listening on 0.0.0.0:8080
2026-01-04 08:12:41 [INFO] request from 192.168.1.42 path=/health status=200
2026-01-04 08:13:02 [INFO] request from 10.0.0.7 path=/api/v1/customers status=200
2026-01-04 08:13:05 [INFO] auth ok user=emily.carter@example.com from 203.0.113.55
2026-01-04 08:13:19 [DEBUG] db pool acquired conn for 172.16.5.88
2026-01-04 08:14:07 [INFO] request from 198.51.100.23 path=/api/v1/loans status=201
2026-01-04 08:14:50 [WARN] slow query 1.8s client=192.168.1.99
2026-01-04 08:15:11 [INFO] auth ok user=james.patel3@sample.io from 10.0.0.14
2026-01-04 08:15:33 [INFO] request from 2001:db8:85a3::8a2e:370:7334 path=/health status=200
2026-01-04 08:16:02 [ERROR] unhandled exception in /api/v1/payments trace=ab12cd
2026-01-04 08:16:40 [WARN] leaked contact in payload phone=(716) 555-1020 client=192.168.1.42
2026-01-04 08:17:21 [INFO] request from 10.0.0.7 path=/api/v1/customers status=200
2026-01-04 08:17:55 [DEBUG] cache miss key=cust:100299481 node=172.16.5.90
2026-01-04 08:18:30 [INFO] auth ok user=linda_nguyen@testmail.org from 203.0.113.77
2026-01-04 08:19:04 [ERROR] ssn appeared in log line ssn=501-22-7788 src=192.168.1.42
2026-01-04 08:19:48 [INFO] request from fe80::1ff:fe23:4567:890a path=/metrics status=200
2026-01-04 08:20:15 [INFO] request from 198.51.100.40 path=/api/v1/loans status=200
2026-01-04 08:20:59 [WARN] rate limit hit for 10.0.0.55 endpoint=/api/v1/search
2026-01-04 08:21:33 [INFO] auth ok user=carlos.ramirez@mail.example.net from 192.168.1.7
2026-01-04 08:22:10 [DEBUG] worker 4 picked job id=8841 from 10.0.0.7
2026-01-04 08:22:44 [INFO] request from 192.168.1.201 path=/health status=200
2026-01-04 08:23:18 [ERROR] payment gateway timeout upstream=203.0.113.90
2026-01-04 08:23:59 [WARN] leaked contact phone=312-555-7741 in note client=10.0.0.7
2026-01-04 08:24:32 [INFO] request from 172.16.8.12 path=/api/v1/customers status=200
2026-01-04 08:25:07 [INFO] auth ok user=aisha.khan21@example.com from 198.51.100.61
2026-01-04 08:25:50 [DEBUG] gc pause 42ms node=192.168.1.42
2026-01-04 08:26:24 [INFO] request from 2001:db8::1 path=/health status=200
2026-01-04 08:27:01 [WARN] retry 2/3 connecting to 10.0.0.250
2026-01-04 08:27:45 [INFO] request from 192.168.1.88 path=/api/v1/loans status=200
2026-01-04 08:28:19 [INFO] shutdown signal received, draining connections
2026-01-04 08:28:33 [INFO] server stopped cleanly
"""


def gen_notes_md() -> str:
    return """\
# Onboarding Notes -- New Clients (SYNTHETIC)

> All names, numbers, and identifiers below are fabricated test data.

## Summary

Met with the **Anderson household** on Tuesday. Primary contact is
Dr. Michael Anderson, who can be reached at michael.anderson@example.com
or (716) 234-2242. His date of birth is 03/14/1981. Mailing address is
482 Maple Avenue, Suite 401, Buffalo, NY 14201.

For the auto-loan portion we recorded the vehicle VIN 1HGBH41JXMN109186
and set up autopay against routing number 021000021, account 100044829017.

## Action items

- [ ] Verify co-applicant Sarah Anderson (SSN 388-21-4410, born July 9, 1983)
- [ ] Collect a voided check to confirm ABA 011401533
- [ ] Scan passport number A1234567 into the file
- [ ] Confirm Driver's license no D2289145 has not expired
- [ ] Email statements to sarah_anderson17@testmail.org

## People

| Name              | Role         | Phone            | Email                            | DOB           |
|-------------------|--------------|------------------|----------------------------------|---------------|
| Dr. Michael Anderson | Applicant | (716) 234-2242   | michael.anderson@example.com     | 03/14/1981    |
| Sarah Anderson    | Co-applicant | +1 716.555.3390  | sarah_anderson17@testmail.org    | July 9, 1983  |
| Jane Williams     | Underwriter  | 312-555-0142     | jane.williams@sample.io          | DOB 1990-05-02|
| Robert Lee        | Escrow       | 414-555-8810     | robert.lee9@sample.io            | born 1977-09-14|

## Misc

Test card used during the demo was Amex 378282246310005. The staging server
that logged the session was at 10.0.0.7 (IPv6 2001:db8:85a3::8a2e:370:7334).
"""


def gen_patients_txt() -> str:
    return """\
LAKESIDE FAMILY HEALTH -- PATIENT INTAKE RECORDS
*** SYNTHETIC TRAINING DATA -- NOT REAL PATIENTS ***

------------------------------------------------------------
Patient: Linda Nguyen
MRN (account): MRN-100571902
D.O.B.: 1979-04-02
Phone: (212) 555-6610
Email: linda.nguyen@testmail.org
Address: 73 Oak Street, Apt 3B, Rochester, NY 14604
Primary care: Dr. Patel
Notes: Patient born on April 2, 1979; no known allergies.

------------------------------------------------------------
Patient: Carlos Ramirez
MRN (account): MRN-100633870
D.O.B.: 09/30/1992
Phone: 303-555-2204
Email: carlos.ramirez@mail.example.net
Address: 55 Cedar Lane, Unit 12, Denver, CO 80202
Primary care: Dr. Emily Carter
Insurance SSN on file: 612-33-7781

------------------------------------------------------------
Patient: Grace Okafor
MRN (account): MRN-100819644
Date of birth: December 1, 1995
Phone: +1 305.555.7720
Email: grace.okafor@inbox.example.org
Address: 318 Highland Drive, Ste 220, Miami, FL 33130
Primary care: Dr. Wei Chen
Notes: Emergency contact George Murphy, (617) 555-7700.

------------------------------------------------------------
Patient: Hiroshi Tanaka
MRN (account): MRN-100888301
D.O.B.: 1982-05-25
Phone: 206-555-4412
Email: hiroshi.tanaka@demo-corp.example
Address: 910 River Road, Seattle, WA 98101
Primary care: Dr. Sarah Anderson
Notes: Patient's birth date 1982-05-25 confirmed against state ID.
"""


SMALL_SAMPLES = {
    "loan-application.txt": gen_loan_application,
    "customers.csv": gen_customers_csv,
    "contacts.json": gen_contacts_json,
    "server.log": gen_server_log,
    "notes.md": gen_notes_md,
    "patients.txt": gen_patients_txt,
}


def regenerate_small() -> None:
    os.makedirs(SAMPLES_DIR, exist_ok=True)
    print(f"Regenerating small samples into {SAMPLES_DIR}", file=sys.stderr)
    total = 0
    for fname, fn in SMALL_SAMPLES.items():
        total += write(os.path.join(SAMPLES_DIR, fname), fn())
    print(f"Done. {len(SMALL_SAMPLES)} files, {total:,} bytes total.",
          file=sys.stderr)


# --------------------------------------------------------------------------
# Large-file generation
# --------------------------------------------------------------------------

def generate_large(rng: random.Random, mb: int | None, rows: int | None,
                   fmt: str) -> None:
    os.makedirs(LARGE_DIR, exist_ok=True)
    target_bytes = mb * 1024 * 1024 if mb is not None else None
    if mb is not None:
        out_name = f"large-{mb}mb.{ 'csv' if fmt == 'csv' else fmt }"
    else:
        out_name = f"large-{rows}rows.{ 'csv' if fmt == 'csv' else fmt }"
    out_path = os.path.join(LARGE_DIR, out_name)

    written = 0
    count = 0
    with open(out_path, "w", encoding="utf-8") as fh:
        if fmt == "csv":
            fh.write(CSV_HEADER)
            written += len(CSV_HEADER)
        while True:
            if fmt == "csv":
                chunk = synth_csv_row(rng)
            elif fmt == "log":
                chunk = synth_log_line(rng)
            else:  # txt
                chunk = synth_record_block(rng, count + 1) + "\n"
            fh.write(chunk)
            written += len(chunk.encode("utf-8"))
            count += 1
            if target_bytes is not None:
                if written >= target_bytes:
                    break
            else:
                if count >= rows:
                    break

    size = os.path.getsize(out_path)
    label = f"~{mb} MB" if mb is not None else f"{rows} rows"
    print(f"Wrote {out_path} ({label}, fmt={fmt}): "
          f"{count:,} records, {size:,} bytes", file=sys.stderr)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(
        description="Generate synthetic PII sample data for pii-redactor.")
    p.add_argument("--large", type=int, action="append", metavar="MB",
                   help="emit a large file of approximately MB megabytes "
                        "(repeatable: --large 5 --large 50 --large 200)")
    p.add_argument("--rows", type=int, default=None,
                   help="emit a large file with exactly N records "
                        "(alternative to --large)")
    p.add_argument("--format", choices=["txt", "csv", "log"], default="txt",
                   help="shape of the large file (default: txt)")
    p.add_argument("--seed", type=int, default=1337,
                   help="random seed (default: 1337, reproducible)")
    args = p.parse_args(argv)

    rng = random.Random(args.seed)

    if not args.large and args.rows is None:
        # No size args -> regenerate the small committed fixtures.
        regenerate_small()
        return 0

    if args.rows is not None and not args.large:
        generate_large(rng, None, args.rows, args.format)
        return 0

    for mb in (args.large or []):
        # Fresh seeded RNG per file so each is independently reproducible.
        generate_large(random.Random(args.seed + mb), mb, None, args.format)
    if args.rows is not None:
        generate_large(random.Random(args.seed + args.rows), None,
                       args.rows, args.format)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
