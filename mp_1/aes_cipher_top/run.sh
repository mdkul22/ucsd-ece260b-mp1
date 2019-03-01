#!/bin/bash

pt_shell -f run_pt.tcl
innovus -batch -execute source -files run_eco.tcl
pt_shell -f eva_pt.tcl

# mailing pre eco reults 
tail -7 aes_cipher_top_sizing.rpt | mail -s "aes_cipher pre-ECO" mkulkarn@eng.ucsd.edu
tail -7 aes_cipher_top_sizing.rpt | mail -s "aes_cipher pre-ECO" teaves@eng.ucsd.edu

# mailing post eco result files
head -5 aes_cipher_top_eco.rpt | mail -s "aes_cipher post-ECO" mkulkarn@eng.ucsd.edu
head -5 aes_cipher_top_eco.rpt | mail -s "aes_cipher post-ECO" teaves@eng.ucsd.edu
