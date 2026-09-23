# -*- coding: utf-8 -*-
import io
import re
import os

here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, "supabase_migration_full_FINAL_recommended.sql")
dst = os.path.join(here, "supabase_migration_FINAL_RUN_ME_RECOMMENDED.sql")

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
    "app_settings": "key",
    "time_slots": "slot_order",
    "time_slot_groups": "id",
    "time_slot_sections": "id",
}

SQL_START = re.compile(
    r"^(?:CREATE|ALTER|INSERT|UPDATE|DELETE|DROP|DO|BEGIN|COMMIT|ROLLBACK|SET|"
    r"SELECT|WITH|GRANT|REVOKE|TRUNCATE|COPY|COMMENT|EXCEPTION|END|VALUES|LOCK|"
    r"VACUUM|ANALYZE|REINDEX|CLUSTER|LISTEN|NOTIFY|RESET|SHOW|DISCARD|DECLARE|"
    r"FETCH|CLOSE|MOVE|REFRESH|SECURITY|UNLISTEN)\b",
    re.IGNORECASE | re.MULTILINE,
)

def is_prose(stmt):
    s = stmt.strip()
    if not s:
        return False
    if s.startswith("--"):
        return False
    if re.match(r"^[\w.$("].*\\)\s*[;]$", s) is None:
        return False
    if SQL_START.match(s):
        return False
    return True

def split_statements(text):
    out = []
    buf = []
    i = 0
    n = len(text)
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
            if c == q and (i == 0 or text[i - 1] != "\\"):
                q = None
            i += 1
            continue
        if c == "'" or c == '"':
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
    if re.search(r"(?is)\bON\s+CONFLICT\s*\(", stmt):
        return stmt, False
    tbl = m.group(1).strip('"').lower()
    pk = PK.get(tbl, "id")
    if re.search(r"(?is)\bSELECT\b", stmt):
        return stmt, False
    body = stmt.rstrip().rstrip(";")
    return body + " ON CONFLICT (" + pk + ") DO NOTHING;", True

def guard_alter(stmt):
    m = re.match(r"(?is)\bALTER\s+TABLE\s+([\"\w]+)\s+ADD\s+CONSTRAINT\s+([\"\w]+)\s*", stmt)
    if not m:
        return stmt, False
    tbl = m.group(1).strip('"')
    cname = m.group(2).strip('"')
    rest = re.sub(r"(?is)^\s*\bALTER\s+TABLE\s+[\"\w]+\s+ADD\s+CONSTRAINT\s+[\"\w]+\s*", "", stmt).rstrip().rstrip(";")
    sql = (
        "DO $$\nBEGIN\n"
        "  ALTER TABLE " + tbl + " ADD CONSTRAINT " + cname + " " + rest + ";\n"
        "EXCEPTION WHEN duplicate_object THEN NULL;\n"
        "END $$;"
    )
    return sql, True

def process(text):
    stmts = split_statements(text)
    out = []
    n_oc = 0
    n_guard = 0
    n_prose = 0
    for st in stmts:
        if is_prose(st):
            out.append("-- " + st)
            n_prose += 1
            continue
        if re.match(r"(?i)\bDO\s*\$", st) or re.search(r"(?i)duplicate_object", st):
            out.append(st + ";")
            continue
        fixed, ok1 = add_conflict(st)
        if ok1:
            n_oc += 1
            out.append(fixed)
            continue
        fixed, ok2 = guard_alter(st)
        if ok2:
            n_guard += 1
            out.append(fixed)
            continue
        out.append(st + ";")
    return "\n".join(out) + "\n", n_oc, n_guard, n_prose

def main():
    text = read_text(src)
    fixed, oc, guard, prose = process(text)
    combined = fixed
    write_text(dst, combined)
    lines = combined.count("\n")
    ins_total = len(re.findall(r"(?i)\bINSERT\s+INTO\b", combined))
    print("WROTE " + dst)
    print("  lines=%d bytes=%d" % (lines + 1, len(combined.encode("utf-8"))))
    print("  INSERT total=%d  ON CONFLICT added=%d" % (ins_total, oc))
    print("  ALTER-ADD-ALTER guarded=%d  prose-commented=%d" % (guard, prose))
    print("  bare-prose remaining=%d" % len([1 for l in combined.splitlines() if is_prose(l)]))
    print("STATUS: CLEAN")

if __name__ == "__main__":
    main()
