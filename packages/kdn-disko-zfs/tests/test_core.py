"""Unit tests for the pure core logic (no host, no nix)."""

import unittest

from kdn_disko_zfs import core


class ComputeIgnoredTest(unittest.TestCase):
    def test_undeclared_live_dataset_is_ignored(self):
        ignored = core.compute_ignored(
            spec_datasets=["pool/fs/var/lib/kdn"],
            live_datasets=["pool", "pool/fs", "pool/fs/var/lib/kdn", "pool/containers", "pool/containers/storage"],
        )
        self.assertEqual(ignored, ["pool/containers", "pool/containers/storage"])

    def test_ancestor_of_declared_is_not_ignored(self):
        # `pool/fs` is an ancestor of the declared dataset, so it must be left alone
        # (neither ignored nor proposed for destroy).
        ignored = core.compute_ignored(
            spec_datasets=["pool/fs/var/lib/kdn"],
            live_datasets=["pool", "pool/fs", "pool/fs/var/lib/kdn"],
        )
        self.assertNotIn("pool/fs", ignored)
        self.assertNotIn("pool", ignored)

    def test_declared_datasets_are_never_ignored(self):
        ignored = core.compute_ignored(
            spec_datasets=["pool/a", "pool/b"],
            live_datasets=["pool/a", "pool/b", "pool/c"],
        )
        self.assertEqual(ignored, ["pool/c"])

    def test_similar_prefix_is_not_mistaken_for_ancestor(self):
        # `pool/ab` must NOT be treated as an ancestor of `pool/a` (prefix without "/").
        ignored = core.compute_ignored(
            spec_datasets=["pool/a"],
            live_datasets=["pool/ab"],
        )
        self.assertEqual(ignored, ["pool/ab"])


class MergeIgnoresTest(unittest.TestCase):
    def test_merges_and_dedupes(self):
        spec = {"datasets": {}, "ignoredDatasets": ["x"], "ignoredProperties": [], "logLevel": "info"}
        merged = core.merge_ignores(spec, ["x", "y"])
        self.assertEqual(merged["ignoredDatasets"], ["x", "y"])
        # original untouched
        self.assertEqual(spec["ignoredDatasets"], ["x"])


class DryRunTest(unittest.TestCase):
    def test_renders_create_with_properties(self):
        spec = {
            "datasets": {
                "pool/ds": {"properties": {"mountpoint": "/ds", "com.sun:auto-snapshot": "false"}},
                "pool/plain": {},
            }
        }
        cmds = core.dry_run_commands(spec)
        self.assertEqual(cmds, [
            "zfs create -omountpoint=/ds -ocom.sun:auto-snapshot=false pool/ds",
            "zfs create pool/plain",
        ])


class DestructiveTest(unittest.TestCase):
    def test_detects_destroy(self):
        self.assertTrue(core.has_destructive("# Destructive\n> zfs destroy pool/x\n"))
        self.assertTrue(core.has_destructive("zfs destroy pool/x"))

    def test_ignores_non_destroy(self):
        text = "# Additive\n> zfs create -omountpoint=/x pool/x\nzfs set acltype=posixacl pool\n"
        self.assertFalse(core.has_destructive(text))


class SpecExprTest(unittest.TestCase):
    def test_expr_mentions_host_and_repo(self):
        expr = core.gen_spec_expr("/repo", "oams")
        self.assertIn('"/repo"', expr)
        self.assertIn('"oams"', expr)
        self.assertIn("disko.devices.zpool", expr)


if __name__ == "__main__":
    unittest.main()
