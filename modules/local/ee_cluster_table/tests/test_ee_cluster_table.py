"""Run with: python3 modules/local/ee_cluster_table/tests/test_ee_cluster_table.py"""

import importlib.util
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep resources/usr/bin free of __pycache__

SCRIPT = Path(__file__).parents[1] / "resources" / "usr" / "bin" / "ee_cluster_table.py"
spec = importlib.util.spec_from_file_location("ee_cluster_table", SCRIPT)
ee_cluster_table = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ee_cluster_table)

CLSTR = """>Cluster 0
0\t2632nt, >s/ctg:25069-27701... *
1\t2107nt, >s/ctg:30874-32981... at 1:2107:503:2617/+/86.81%
>Cluster 1
0\t1101nt, >s/ctg:55514-56615... at 1101:1:204:1303/-/99.27%
1\t1324nt, >s/ctg:58251-59575... *
>Cluster 2
0\t900nt, >s/ctg:1-900... *
"""

rows = {row["sequence_id"]: row for row in ee_cluster_table.parse_clstr(CLSTR.splitlines(True), "s")}

# a representative matches itself
assert rows["s/ctg:25069-27701"]["is_representative"] == "true"
assert rows["s/ctg:25069-27701"]["identity"] == "100.00"
# a member: identity from cd-hit, coverage of each sequence from the coordinates
member = rows["s/ctg:30874-32981"]
assert member["cluster_id"] == "s_cl1"
assert member["representative_id"] == "s/ctg:25069-27701"
assert member["identity"] == "86.81"
assert member["member_coverage"] == "100.00"
assert member["representative_coverage"] == f"{2115 / 2632 * 100:.2f}"
# the representative is not always listed first; the minus strand reverses the member coordinates
reverse = rows["s/ctg:55514-56615"]
assert reverse["representative_id"] == "s/ctg:58251-59575"
assert reverse["member_coverage"] == "100.00"
# a singleton is its own cluster
assert rows["s/ctg:1-900"]["cluster_id"] == "s_cl3"

# a .clstr without the -p 1 coordinates is an error, not a silent table
try:
    ee_cluster_table.parse_clstr([">Cluster 0\n", "0\t900nt, >x... at +/90.00%\n"], "s")
except ValueError:
    pass
else:
    raise AssertionError("a .clstr without -p 1 must raise")

# vclust: member -> representative, with ANI and coverages from the align table
VCLUST_CLUSTERS = "object\tcluster\na\ta\nb\ta\nc\ta\nd\td\n".splitlines(True)
VCLUST_ALIGN = (
    "qidx\tridx\tquery\treference\ttani\tgani\tani\tqcov\trcov\tnum_alns\tlen_ratio\n"
    "1\t0\tb\ta\t0.9\t0.9\t0.95\t0.90\t0.85\t1\t0.9\n"
    "0\t2\ta\tc\t0.9\t0.9\t0.97\t0.80\t1.00\t1\t0.8\n"
).splitlines(True)
lengths = {"a": 1000, "b": 950, "c": 800, "d": 1200}
rows = {row["sequence_id"]: row for row in ee_cluster_table.parse_vclust(VCLUST_CLUSTERS, VCLUST_ALIGN, lengths, "s")}
# numbered from the longest representative, like cd-hit-est
assert rows["d"]["cluster_id"] == "s_cl1" and rows["a"]["cluster_id"] == "s_cl2"
assert rows["a"]["is_representative"] == "true" and rows["a"]["identity"] == "100.00"
assert (rows["b"]["identity"], rows["b"]["member_coverage"], rows["b"]["representative_coverage"]) == ("95.00", "90.00", "85.00")
# only representative -> member was aligned: the coverages swap
assert (rows["c"]["member_coverage"], rows["c"]["representative_coverage"]) == ("100.00", "80.00")

# no clusters (one element, which vclust cannot align): each element its own cluster
rows = ee_cluster_table.singletons({"x": 500}, "s")
assert len(rows) == 1 and rows[0]["cluster_id"] == "s_cl1" and rows[0]["is_representative"] == "true"

print("ok")
