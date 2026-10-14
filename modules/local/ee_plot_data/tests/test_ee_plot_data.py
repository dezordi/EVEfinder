"""Run with: python3 modules/local/ee_plot_data/tests/test_ee_plot_data.py"""

import csv
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True  # keep resources/usr/bin free of __pycache__

SCRIPT = Path(__file__).parents[1] / "resources" / "usr" / "bin" / "ee_plot_data.py"
spec = importlib.util.spec_from_file_location("ee_plot_data", SCRIPT)
ee_plot_data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ee_plot_data)

# NIRV: RNA and not retroviral
assert ee_plot_data.is_nirv("ssRNA(+)") and ee_plot_data.is_nirv("dsRNA") and ee_plot_data.is_nirv("RNA")
assert not ee_plot_data.is_nirv("ssRNA-RT") and not ee_plot_data.is_nirv("dsDNA-RT")
assert not ee_plot_data.is_nirv("dsDNA") and not ee_plot_data.is_nirv("ssDNA(+/-)")

# missing ranks and EEfinder's own Unk are both Unk
taxonomy = ee_plot_data.parse_taxonomy("r__Unk;k__Unk;f__Polydnaviriformidae;g__Bracoviriform")
assert taxonomy["realm"] == "Unk" and taxonomy["family"] == "Polydnaviriformidae"
assert taxonomy["species"] == "Unk"

assert ee_plot_data.safe_name("ssRNA(+/-)") == "ssRNA+-"
assert ee_plot_data.safe_name("dsDNA;ssRNA(+)") == "dsDNA_ssRNA+"

TAX = """element_id\tsense\tprotein_ids\tprotein_products\tmolecule_type\ttaxonomy\thost\toverlaped_element_id\ttag\taverage_pident
ctg:0-10\tneg\ta|30\tpolymerase AND capsid\tssRNA(+)\tr__Riboviria;k__Orthornavirae;f__Flaviviridae\tx\t\tunique\t30
ctg:20-25\tpos\tb|40\tPol\tssRNA-RT\tr__Riboviria;k__Pararnavirae;o__Ortervirales;f__Metaviridae\tx\t\tunique\t40
ctg:30-34\tpos\tc|40\tNS1\tssRNA(+)\tr__Riboviria;k__Orthornavirae;f__Flaviviridae\tx\t\tunique\t40
ctg:40-42\tneg\td|45\tKinase\t\tf__Polydnaviriformidae\tx\t\tunique\t45
"""
FASTA = ">s1/ctg:0-10\nACGTACGTAC\n>s1/ctg:20-25\nACG\nTA\n>s1/ctg:30-34\nACGT\n>s1/ctg:40-42\nAC\n"

with tempfile.TemporaryDirectory() as tmp:
    os.chdir(tmp)
    Path("s1.EEs.tax.tsv").write_text(TAX)
    Path("s1.EEs.fa").write_text(FASTA)
    sys.argv = ["ee_plot_data.py", "--samples", "s1", "s2"]
    ee_plot_data.main()

    rows = list(csv.DictReader(open("elements.tsv"), delimiter="\t"))
    assert [r["length"] for r in rows] == ["10", "5", "4", "2"]
    assert rows[3]["molecule_type"] == "Unk"  # empty in the database
    assert rows[0]["protein"] == "polymerase"  # the first of several proteins
    assert [r["nirv"] for r in rows] == ["true", "false", "true", "false"]
    assert rows[0]["order"] == "Unk" and rows[1]["order"] == "Ortervirales"
    # a genome without elements is still listed
    assert Path("genomes.tsv").read_text() == "sample\telements\ns1\t4\ns2\t0\n"

    krona = Path("krona/s1")
    assert sorted(p.name for p in krona.iterdir()) == ["NIRV.txt", "Unk.txt", "all.txt", "ssRNA+.txt", "ssRNA-RT.txt"]
    # a path ends at its last known rank, and identical paths are counted together
    assert (krona / "NIRV.txt").read_text() == "2\tRiboviria\tOrthornavirae\tUnk\tUnk\tUnk\tFlaviviridae\n"
    assert not Path("krona/s2").exists()

print("ee_plot_data: all checks passed")
