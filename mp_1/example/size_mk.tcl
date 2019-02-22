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

define_user_attribute -type float -class cell P_custom
set cellList [sort_collection [get_cells *] base_name]
set VtswapCnt 0
set SizeswapCnt 0

proc findmax { Plist } {
  set max 0
  set count 0
  foreach i $Plist {
    if { $i > $max } {
      set max $i
      set count [ expr $count + 1 ]
    }
  }
  return [ list $max $count ]
}
proc ComputeSensitivity { cellName } {
  return 0.65
}

foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {[$libcellName == "ms00f80"]} {
        continue
    }
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
    set_user_attribute [get_cells $cell] P_custom [ComputeSensitivity $cellName]
    puts [ComputeSensitivity $cellName]
}
puts "\ndone with first loop\n"

add_to_collection $S_cells [ sort_collection -descending [get_cells *] P_custom ]
set Pmax [ get_attri [ index_collection $S_cells 0 ] P_custom ]

while { [ expr $Pmax > 0.0 ] } {
  # get max value and iterator to get cell from collection
  set cell [ index_collection $S_cells 0 ]
  set cellName [get_attri $cell base_name]
  set libcell [get_lib_cells -of_objects $cellName]
  set libcellName [get_attri $libcell base_name]
  # removing value Pmax from List
  set S_cells [remove_from_collection $S_cells $cellName]
  if {[$libcellName == "ms00f80"]} {
      continue
  }
  set newlibcellName [ getNextSizeDown $libcellName ]
  size_cell $cellName $newlibcellName
  set time_violation [ CISTA $cellName ]
  if { time_violation }
  {
    size_cell $cellName $libcellName
  }
  else {
    set fan_in_cells [all_fanin - ]
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
