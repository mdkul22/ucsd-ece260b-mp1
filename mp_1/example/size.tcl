set design [get_attri [current_design] full_name]
set outFp [open ${design}_sizing.rpt w]

set initialWNS  [ PtWorstSlack clk ]
set initialLeak [ PtLeakPower ]
set capVio [ PtGetCapVio ]
set tranVio [ PtGetTranVio ]
puts "Initial slack:\t${initialWNS} ps"
puts "Initial leakage:\t${initialLeak} W"
puts "Final $capVio"
puts "Final $tranVio"
puts "======================================" 
puts $outFp "Initial slack:\t${initialWNS} ps"
puts $outFp "Initial leakage:\t${initialLeak} W"
puts $outFp "Final $capVio"
puts $outFp "Final $tranVio"
puts $outFp "======================================" 

proc GetCapVPins { } {

  global sh_product_version
  global sh_dev_null
  global pt_tmp_dir
  global report_default_significant_digits
  global synopsys_program_name

  redirect $pt_tmp_dir/tmp.[pid] {report_constraint -all_violators -nosplit -significant_digits 5 -max_capacitance}

  set REPORT_FILE [open $pt_tmp_dir/tmp.[pid] r]
  set drc_list ""
  set cost 0.0
  set count 0
  set max_cost 0

  set capVioPins ""
  while {[gets $REPORT_FILE line] >= 0} {
    switch -regexp $line {
      {(^.*\/[a-zA-Z]) .* +\(VIOLATED)} {
          regexp {(^.*\/[a-zA-Z]) .* +\(VIOLATED)} $line full pin
              lappend capVioPins $pin
              continue
      }
    }
  }

  close $REPORT_FILE
    return $capVioPins
}

set cellList [sort_collection [get_cells *] base_name]
set VtswapCnt 0
set SizeswapCnt 0
foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {$libcellName == "ms00f80"} {
        continue
    }
    set newlibcellName [string replace $libcellName 5 6 "01" ]
    size_cell $cellName $newlibcellName
    incr SizeswapCnt
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
    set COMMENT { if { [regexp {[a-z][a-z][0-9][0-9]f[0-9][0-9]} $libcellName] } { 
        set newlibcellName [string replace $libcellName 4 4 s] 
        size_cell $cellName $newlibcellName
        
        set COMMENT { set newWNS [ PtWorstSlack clk ]
        if { $newWNS < 0.0 } {
            size_cell $cellName $libcellName
        } else {
            incr VtswapCnt
            puts $outFp "- cell ${cellName} is swapped to $newlibcellName"
        }
        }
    }
   
    if { [regexp {[a-z][a-z][0-9][0-9]m[0-9][0-9]} $libcellName] } { 
        set newlibcellName [string replace $libcellName 4 4 s] 
        size_cell $cellName $newlibcellName
        
        set COMMENT { set newWNS [ PtWorstSlack clk ]
        if { $newWNS < 0.0 } {
            size_cell $cellName $libcellName
        } else {
            incr VtswapCnt
            puts $outFp "- cell ${cellName} is swapped to $newlibcellName"
        }
        }
    }
    }
    #cell size swap example (convert all cells of size 08 to 04)...
    set COMMENT { if { [regexp {[a-z][a-z][0-9][0-9][smf]04} $libcellName] } { 
        set newlibcellName [string replace $libcellName 5 6 "02"]
        size_cell $cellName $newlibcellName
        #added by me
        incr SizeswapCnt         
   
        set COMMENT { set newWNS [ PtWorstSlack clk ]
        if { $newWNS < 0.0 } {
            size_cell $cellName $libcellName
        } else {
            incr SizeswapCnt
            puts $outFp "- cell ${cellName} is swapped to $newlibcellName"
        }
        }
    }
    if { [regexp {[a-z][a-z][0-9][0-9][smf]08} $libcellName] } { 
        set newlibcellName [string replace $libcellName 5 6 "04"]
        size_cell $cellName $newlibcellName
        #added by me
        incr SizeswapCnt        
         
        set COMMENT { set newWNS [ PtWorstSlack clk ]
        if { $newWNS < 0.0 } {
            size_cell $cellName $libcellName
        } else {
            incr SizeswapCnt
            puts $outFp "- cell ${cellName} is swapped to $newlibcellName"
        }
        }
    }
    }

}

set val [ PtGetCapVio ]
set vioPins [ GetCapVPins ]
set violations [ llength $vioPins ]

foreach pin $vioPins {
  set source_cell [get_cells -of_objects [get_pins $pin]]
  set fan_out_gates [all_fanout -from [get_pins $pin] -only_cells]
  foreach_in_collection fcell $fan_out_gates {
    set cellName [get_attri $fcell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]

    set newlibcellName [getNextSizeDown $libcellName]
    if {$newlibcellName != "skip"} {
      size_cell $cellName $newlibcellName
      update_timing
      set wns [PtWorstSlack clk]
      if {$wns<0} {
        size_cell $cellName $libcellName
        continue
      }
    }
  }
  set val [ PtGetCapVio ]
  set check_pins [ GetCapVPins ]
  set no_of_pins [ llength $check_pins ]
  if { $no_of_pins < $vioPins } {
    set vioPins $no_of_pins
  } else {
  set source_cell [get_cells -of_objects [get_pins $pin]]
  set cellName [get_attri $source_cell base_name]
  set libcell [get_lib_cells -of_objects $cellName]
  set libcellName [get_attri $libcell base_name]
  set newlibcellName [getNextSizeUp $libcellName]
  size_cell $cellName $newlibcellName
  }
}

set finalWNS  [ PtWorstSlack clk ]
set finalLeak [ PtLeakPower ]
set capVio [ PtGetCapVio ]
set tranVio [ PtGetTranVio ]
set improvment  [format "%.3f" [expr ( $initialLeak - $finalLeak ) / $initialLeak * 100.0]]
puts $outFp "======================================" 
puts $outFp "Final slack:\t${finalWNS} ps"
puts $outFp "Final leakage:\t${finalLeak} W"
puts $outFp "Final $capVio"
puts $outFp "Final $tranVio"
puts $outFp "#Vt cell swaps:\t${VtswapCnt}"
puts $outFp "#Cell size swaps:\t${SizeswapCnt}"
puts $outFp "Leakage improvment\t${improvment} %"

close $outFp    


