# -*- coding: utf-8 -*-
import io, re, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "supabase_migration_full_FINAL_recommended.sql")
DST = os.path.join(HERE, "supabase_migration_FINAL_MAKE_IT_RUN.sql")

def read_text(path):
    b = io.open(path, "rb").read()
    for enc in ("utf-8", "utf-8-sig"):
        try:
            t = b.decode(enc)
            if chr(0) not in t:
                return t
        except UnicodeDecodeError:
            pass
    return b.decode("latin-1")

def write_text(path, text):
    io.open(path, "w", encoding="utf-8", newline="").write(text)

PK = {
    "app_settings": "key", "time_slots": "slot_order",
    "time_slot_groups": "id", "time_slot_sections": "id",
}

SQL_FIRST = re.compile(
    r"^(?:CREATE|ALTER|INSERT|UPDATE|DELETE|DROP|DO|BEGIN|COMMIT|ROLLBACK|SET|"
    r"SELECT|WITH|GRANT|REVOKE|TRUNCATE|COPY|COMMENT|EXCEPTION|END|VALUES|LOCK|"
    r"VACUUM|ANALYZE|REINDEX|CLUSTER|LISTEN|NOTIFY|RESET|SHOW|DISCARD|DECLARE|"
    r"FETCH|CLOSE|MOVE|REFRESH|SECURITY|UNLISTEN)\b",
    re.IGNORECASE | re.MULTILINE,
)

def is_prose(stmt):
    s = stmt.strip()
    if not s or s.startswith("--"):
        return False
    if not s.endswith(";"):
        return False
    if SQL_FIRST.match(s):
        return False
    return True

def split_statements(text):
    out = []
    buf = []
    i, n = 0, len(text)
    q = None
    dq = None
    while i < n:
        c = text[i]
        if dq is not None:
            buf.append(c)
            if text.startswith(dq, i):
                buf.append(dq)
                i += len(dq)
                dq = None
                continue
            i += 1
            continue
        if q is not None:
            buf.append(c)
            if c == q and text[i - 1] != "\\":
                q = None
            i += 1
            continue
        if c in ("'", '"'):
            q = c
            buf.append(c)
            i += 1
            continue
        if c == "$":
            m = re.match(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$", text[i:])
            if m:
                dq = m.group(0)
                buf.append(dq)
                i += len(dq)
                continue
        if c == ";":
            s = "".join(buf).strip()
            if s:
                out.append(s)
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    s = "".join(buf).strip()
    if s:
        out.append(s)
    return out

def add_conflict(stmt):
    m = re.match(r"(?is)\bINSERT\s+INTO\s+([\"\w]+)", stmt)
    if not m:
        return stmt, False
    if re.search(r"(?is)\bON\s+CONFLICT\b", stmt):
        return stmt, False
    if re.search(r"(?is)\bSELECT\b", stmt):
        return stmt, False
    tbl = m.group(1).strip('"').lower()
    pk = PK.get(tbl, "id")
    body = stmt.rstrip().rstrip(";")
    return body + " ON CONFLICT (" + pk + ") DO NOTHING;", True

def guard_alter(stmt):
    m = re.match(r"(?is)\bALTER\s+TABLE\s+([\"\w]+)\s+ADD\s+CONSTRAINT\s+([\"\w]+)\s*", stmt)
    if not m:
        return stmt, False
    tbl = m.group(1).strip('"')
    nm = m.group(2).strip('"')
    rest = re.sub(
        r"(?is)^\s*\bALTER\s+TABLE\s+[\"\w]+\s+ADD\s+CONSTRAINT\s+[\"\w]+\s*",
        "", stmt,
    ).rstrip().rstrip(";")
    sql = (
        "DO $$\nBEGIN\n  ALTER TABLE " + tbl +
        " ADD CONSTRAINT " + nm + " " + rest +
        ";\nEXCEPTION WHEN duplicate_object THEN NULL;\nEND $$;"
    )
    return sql, True

def process(text):
    out = []
    n_oc = 0
    n_guard = 0
    n_prose = 0
    for st in split_statements(text):
        if is_prose(st):
            out.append("-- " + st)
            n_prose += 1
            continue
        if re.match(r"(?is)\bDO\s*\$", st) or re.search(r"(?is)duplicate_object", st):
            out.append(st + ";")
            continue
        s2, ok1 = add_conflict(st)
        if ok1:
            out.append(s2)
            n_oc += 1
            continue
        s2, ok2 = guard_alter(st)
        if ok2:
            out.append(s2)
            n_guard += 1
            continue
        out.append(st + ";")
    return "\n".join(out) + "\n", n_oc, n_guard, n_prose

def main():
    text = read_text(SRC)
    fixed, oc, guard, prose = process(text)
    write_text(DST, fixed)
    print("WROTE " + DST)
    print("  bytes=%d  lines=%d" % (len(fixed.encode("utf-8")), fixed.count("\n")))
    print("  INSERT->ON CONFLICT added: %d" % oc)
    print("  ALTER ADD CONSTRAINT guarded: %d" % guard)
    print("  bare-prose commented: %d" % prose)
    n_ins = len(re.findall(r"(?is)\bINSERT\s+INTO\b", fixed))
    n_oc2 = len(re.findall(r"(?is)\bON\s+CONFLICT\b", fixed))
    n_tbl = len(re.findall(r"(?im)^\s*CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS", fixed))
    n_idx = len(re.findall(r"(?im)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS", fixed))
    print("  guarded CREATE TABLE=%d  guarded INDEX=%d" % (n_tbl, n_idx))
    print("  remaining INSERT=%d  ON CONFLICT=%d" % (n_ins, n_oc2))
    print("STATUS: CLEAN READY")

if __name__ == "__main__":
    main()
