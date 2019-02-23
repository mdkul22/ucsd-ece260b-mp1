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

proc CISTA { cellname } {
return 1
}

proc computeSensitivity { cellName } {
    #get old info
    set old_slack [ PtCellSlack $cellName ]
    set old_leak  [ PtCellLeak  $cellName ]

    #get the current libcellName. this will be the save state
    set libcell [ get_lib_cells -of_objects $cellName ]
    set libcellName [ get_attri $libcell base_name ]

    #downsize the cell, first testing if it's not already minimum size
    #returns zero sensitivity if can't be downsized
    if { [ getNextSizeDown $libcellName ] == "skip" } {
       return 0
    }
    set newlibcellName [ getNextSizeDown $libcellName ]
    set min_flag [ size_cell  $cellName $newlibcellName ]
    if { [ expr $min_flag == 0 ]  } {
       return 0
    }
    size_cell $cellName $newlibcellName

    #create collection of all fan in cells
    #set fanin [ all_fanin -to $news_size ]

    #get new info
    set new_slack [ PtCellSlack $cellName ]
    set new_leak  [ PtCellLeak  $cellName ]

    #restore state
    size_cell $cellName $libcellName

    return [ expr ($old_leak - $new_leak)/($old_slack - $new_slack) ]
}

foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {$libcellName == "ms00f80"} {
        continue
    }
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
    set_user_attribute [get_cells $cellName] P_custom [computeSensitivity $cellName]
}
puts "\ndone with first loop\n"
set S_cells []
set S_cells [ sort_collection -descending [get_cells *] P_custom ]
foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {$libcellName == "ms00f80"} {
      set S_cells [remove_from_collection $cell cellName]
    }
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
}
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
  if { $time_violation }
  {
    size_cell $cellName $libcellName
  }
  else {
    set cellPins [get_pins -of_objects $cellName]
    set fan_in_gates [all_fanin -to $cellPins -only_cells]
    set fan_out_gates [all_fanout -from $cellPins -only_cells]
    set gate_list []
    add_to_collection $gate_list $fan_in_gates
    add_to_collection $gate_list $fan_out_gates
    foreach_in_collection gate $gate_list {
          set_user_attribute [get_cells $gate] P_custom [computeSensitivity $cellName]
    }
  }
# Find Pmax by sorting cells and looping again
add_to_collection $S_cells [ sort_collection -descending [get_cells *] P_custom ]
set Pmax [ get_attri [ index_collection $S_cells 0 ] P_custom ]
if { expr [$Pmax < 0]} {
  break
}
if { expr [[sizeof_collection $S_cells] == 0]}
{
  break
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
