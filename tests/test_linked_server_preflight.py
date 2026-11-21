"""Static safety contracts; no SQL client, server, credentials, or network needed."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "QueryVault/Preflight/InspectLinkedServer.sql"


def code_without_comments_or_literals(sql):
    # Keep tokens in executable SQL while removing comments and quoted values.
    return re.sub(r"/\*.*?\*/|--[^\n]*|N?'(?:''|[^'])*'", " ", sql,
                  flags=re.DOTALL | re.IGNORECASE)


class LinkedServerInspectionSafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = SCRIPT.read_text(encoding="utf-8")
        cls.code = code_without_comments_or_literals(cls.sql)

    def test_local_catalog_allowlist(self):
        # No endpoint query, user table, DMV, or other system catalog is allowed.
        sources = re.findall(r"\b(?:FROM|JOIN)\s+([^\s;,()]+)", self.code, re.I)
        self.assertEqual(set(source.lower() for source in sources),
                         {"sys.servers", "sys.linked_logins", "@link"})
        self.assertEqual(sources.count("sys.servers"), 1)
        self.assertEqual(sources.count("sys.linked_logins"), 1)
        self.assertNotRegex(self.code, r"(?i)\b(OPENQUERY|OPENROWSET|OPENDATASOURCE|EXEC|EXECUTE)\b")

    def test_no_persistent_or_security_changes(self):
        self.assertNotRegex(self.code, r"(?i)\b(CREATE|ALTER|DROP|UPDATE|DELETE|TRUNCATE|MERGE|GRANT|DENY|REVOKE|DBCC|BACKUP|RESTORE)\b")
        inserts = re.findall(r"\bINSERT\s+(?:INTO\s+)?([^\s(]+)", self.code, re.I)
        self.assertEqual(inserts, ["@Link"])
        self.assertNotRegex(self.code, r"(?i)\b(BEGIN\s+TRAN|COMMIT|ROLLBACK|SET)\b")

    def test_secret_and_network_columns_never_read(self):
        self.assertNotRegex(self.code, r"(?i)\b(provider_string|remote_name|data_source|location|catalog|password|credential_identity|secret)\b")
        self.assertNotRegex(self.code, r"(?i)\bSELECT\s+(?:\w+\.)?\*")

    def test_exact_name_and_selected_link_scope(self):
        self.assertRegex(self.code, r"(?i)WHERE\s+name\s+COLLATE\s+Latin1_General_100_BIN2\s*=\s*@LinkedServerName\s+COLLATE\s+Latin1_General_100_BIN2")
        self.assertRegex(self.code, r"(?i)DATALENGTH\(name\)\s*=\s*DATALENGTH\(@LinkedServerName\)")
        self.assertRegex(self.code, r"(?i)AND\s+server_id\s*>\s*0\s+AND\s+is_linked\s*=\s*1")
        self.assertRegex(self.code, r"(?i)FROM\s+sys\.linked_logins\s+WHERE\s+server_id\s*=\s*@ServerID\s*;")
        self.assertNotRegex(self.code, r"(?i)\bLIKE\b")

    def test_no_interpolation_or_default_target(self):
        self.assertNotIn("$(", self.sql)
        self.assertNotRegex(self.code, r"(?im)^\s*GO\s*$")
        self.assertNotRegex(self.code, r"(?i)(?:DECLARE|SET|SELECT)\s+@LinkedServerName\b")
        self.assertRegex(self.code, r"(?i)@LinkedServerName\s+IS\s+NULL")
        self.assertRegex(self.code, r"(?i)DATALENGTH\(@LinkedServerName\)\s*>\s*256")
        self.assertRegex(self.code, r"(?i)COUNT\(\*\)\s+FROM\s+@Link\)\s*<>\s*1")
        self.assertRegex(self.code, r"(?i)THROW\s+51650\b")
        self.assertRegex(self.code, r"(?i)THROW\s+51651\b")

    def test_report_cannot_be_interpreted_as_remote_success(self):
        self.assertRegex(self.code, r"(?i)CAST\(0\s+AS\s+BIT\)\s+AS\s+CanStartCollection")
        for field in ("RemoteConnectivity", "QueryStoreAccess"):
            self.assertRegex(self.sql, rf"N'NOT_TESTED'\s+AS\s+{field}\b")
        for field in ("TlsValidation", "EffectiveExecutionIdentity"):
            self.assertRegex(self.sql, rf"N'NOT_ASSESSED'\s+AS\s+{field}\b")
        self.assertRegex(self.sql, r"N'MAY_BE_FILTERED'\s+AS\s+MappingVisibility")
        self.assertIn("N'BLOCKED_NO_VISIBLE_MAPPING'", self.sql)
        self.assertIn("N'BLOCKED_DATA_ACCESS_DISABLED'", self.sql)


if __name__ == "__main__":
    unittest.main()
