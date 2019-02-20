#!/bin/bash

pt_shell -f run_pt.tcl
innovus -batch -execute source -files run_eco.tcl
pt_shell -f eva_pt.tcl

# mailing result files
head -4 usb_phy_sizing.rpt | mail -s "Results from the run" mkulkarn@eng.ucsd.edu
head -4 usb_phy_sizing.rpt | mail -s "Results from the run" teaves@eng.ucsd.edu
