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

define_user_attribute -type string -class cell P_Gate
define_user_attribute -type string -class cell P_Vt
set cellList [sort_collection [get_cells *] base_name]
set VtswapCnt 0
set SizeswapCnt 0
# this checks fan-in and fan-out nodes of the cell and gives back the appropriate result
proc CISTA { cellName } {
  set cellPins [get_pins -of_objects $cellName]
  set fan_in_gates [all_fanin -to $cellPins -only_cells]
  set fan_out_gates [all_fanout -from $cellPins -only_cells]
  # add fanin fanout nodes
  set gate_list $fan_in_gates
  add_to_collection $gate_list $fan_out_gates
  set violation 0
  foreach_in_collection gate $gate_list {
      set gate_slack [PtCellSlack gate]
      if {$gate_slack < 0} {
        return 1
      } else {
        set violation 0
      }
  }
  return violation
}
# needs work
proc EISTA { cellname } {
  set cellPins [get_pins -of_objects $cellName]
  set fan_in_cells [fanin_path $cellName ]
  set fan_out_cells [fanout_path $cellName]
return 0
}
# calculates Vt Sensitivity
proc computeSensitivityVT { cellName } {
   set old_slack [ PtCellSlack $cellName ]
   set old_leak  [ PtCellLeak  $cellName ]

   set libcell [ get_lib_cells -of_objects $cellName ]
   set libcellName [ get_attri $libcell base_name ]

   #may need check here if Vt is already max?
   if { [ getNextVtDown $libcellName ] == "skip" } {
      return [ get_attri [ get_cells $cellName ] P_Gate ]
   }
   #the getnextVT functions are defined such that up and down refer to
   #speed, not threshold level.  getNextVtDown actually raises VT, also
   #it returns skip if already an HVT
   set newlibcellName [ getNextVtDown $libcellName ]
   set max_flag [ size_cell $cellName $newlibcellName ]
   if { [ expr $max_flag == 0 ] } {
      return [ get_attri [ get_cells $cellName ] P_Gate ]
   }

   set new_slack [ PtCellSlack $cellName ]
   set new_leak  [ PtCellLeak $cellName  ]

   #restore state
   size_cell $cellName $libcellName

   return [ expr ($old_leak - $new_leak)/($old_slack - $new_slack) ]
}
# calculates gate sensitivity
proc computeGateSensitivity { cellName } {
    #get old info
    set old_slack [ PtCellSlack $cellName ]
    set old_leak  [ PtCellLeak  $cellName ]

    #get the current libcellName. this will be the save state
    set libcell [ get_lib_cells -of_objects $cellName ]
    set libcellName [ get_attri $libcell base_name ]

    #downsize the cell, first testing if it's not already minimum size
    #returns zero sensitivity if can't be downsized
    if { [ getNextSizeDown $libcellName ] == "skip" } {
       return [ get_attri [ get_cells $cellName ] P_Gate ]
    }
    set newlibcellName [ getNextSizeDown $libcellName ]
    set min_flag [ size_cell  $cellName $newlibcellName ]
    if { [ expr $min_flag == 0 ]  } {
       return [ get_attri [ get_cells $cellName ] P_Gate ]
    }

    #create collection of all fan in cells
    #set fanin [ all_fanin -to $news_size ]

    #get new info
    set new_slack [ PtCellSlack $cellName ]
    set new_leak  [ PtCellLeak  $cellName ]

    #restore state
    set b [ size_cell $cellName $libcellName ]
    return [ expr ($old_leak - $new_leak)/($old_slack - $new_slack) ]
}

puts [ sizeof_collection $cellList ]

# P_Gate and P_Vt
foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {$libcellName == "ms00f80"} {
        continue
    }
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
    set_user_attribute [get_cells $cellName] P_Gate 0
    set_user_attribute [get_cells $cellName] P_Gate [computeGateSensitivity $cellName]
    set_user_attribute [get_cells $cellName] P_Vt 0
    set_user_attribute [get_cells $cellName] P_Vt [computeSensitivityVT $cellName]
}

puts "\ndone with first loop\n"

set S_cells []
set S_cells [ sort_collection -descending [get_cells *] P_Vt ]



foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {$libcellName == "ms00f80"} {
      set S_cells [remove_from_collection $S_cells $cell]
    }
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
}
set Pmax [ get_attri [ index_collection $S_cells 0 ] P_Vt ]
# Pmax
while {  $Pmax > 0.0 } {
  # get max value and iterator to get cell from collection
  set cell [ index_collection $S_cells 0 ]
  set cellName [get_attri $cell base_name]
  set libcell [get_lib_cells -of_objects $cellName]
  set libcellName [get_attri $libcell base_name]
  set size [sizeof_collection $S_cells]
  if { $size == 0} {
    break
  }
  # removing value Pmax from List
  #set S_cells [remove_from_collection $S_cells $cellName]
  if {$libcellName == "ms00f80"} {
      continue
  }
  set newlibcellName [ getNextVtDown $libcellName ]
  if {$newlibcellName == "skip"} {
    #size_cell $cellName $libcellName
    set S_cells [ remove_from_collection $S_cells $cellName ]
    continue
  }
  #check if sizeable, if not remove from list
  set sizeable [size_cell $cellName $newlibcellName]
  # doing incremental timing of all cell paths to ensure no faults
  update_timing
  # checking if WNS is less than zero or not
  set new_wns [ PtWorstSlack clk ]
  if {$new_wns < 0 || $sizeable == 0} {
    size_cell $cellName $libcellName
    set S_cells [ remove_from_collection $S_cells $cellName ]
    continue
  }

  set time_violation [ CISTA $cellName ]
  if {$time_violation == 1} {
    puts {time violated}
    size_cell $cellName $libcellName
  } else {
    set cellPins [get_pins -of_objects $cellName]
    set fan_in_gates [all_fanin -to $cellPins -only_cells]
    set fan_out_gates [all_fanout -from $cellPins -only_cells]
    set gate_list $fan_in_gates
    add_to_collection $gate_list $fan_out_gates
    add_to_collection $gate_list $cellName
    foreach_in_collection gate $gate_list {
      	set_user_attribute [get_cells $gate] P_VT [computeSensitivityVT $gate]
    }
    set next_sizeable [getNextVtDown $newlibcellName]
    if {$next_sizeable == "skip"} {
      set S_cells [ remove_from_collection $S_cells $cellName ]
    }
  }

  # Find Pmax by sorting cells and looping again
  set S_cells [ sort_collection -descending $S_cells P_Gate ]

  set Pmax [ get_attri [ index_collection $S_cells 0 ] P_Gate ]
  if { $Pmax < 0 } {
    break
  }
  set size [sizeof_collection $S_cells]
  if { $size == 0} {
    break
  }
}

set S_cells []
set S_cells [ sort_collection -descending [get_cells *] P_Gate ]
foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {$libcellName == "ms00f80"} {
      set S_cells [remove_from_collection $S_cells $cell]
    }
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
}
set Pmax [ get_attri [ index_collection $S_cells 0 ] P_Gate ]
# Pmax
while {  $Pmax > 0.0 } {
  # get max value and iterator to get cell from collection
  set cell [ index_collection $S_cells 0 ]
  set cellName [get_attri $cell base_name]
  set libcell [get_lib_cells -of_objects $cellName]
  set libcellName [get_attri $libcell base_name]
  set size [sizeof_collection $S_cells]
  if { $size == 0} {
    break
  }
  # removing value Pmax from List
  #set S_cells [remove_from_collection $S_cells $cellName]
  if {$libcellName == "ms00f80"} {
      continue
  }
  set newlibcellName [ getNextSizeDown $libcellName ]
  if {$newlibcellName == "skip"} {
    #size_cell $cellName $libcellName
    set S_cells [ remove_from_collection $S_cells $cellName ]
    continue
  }
  #check if sizeable, if not remove from list
  set sizeable [size_cell $cellName $newlibcellName]
  # doing incremental timing of all cell paths to ensure no faults
  update_timing
  # checking if WNS is less than zero or not
  set new_wns [ PtWorstSlack clk ]
  if {$new_wns < 0 || $sizeable == 0} {
    size_cell $cellName $libcellName
    set S_cells [ remove_from_collection $S_cells $cellName ]
    continue
  }

  set time_violation [ CISTA $cellName ]
  if {$time_violation == 1} {
    puts {time violated}
    size_cell $cellName $libcellName
  } else {
    set cellPins [get_pins -of_objects $cellName]
    set fan_in_gates [all_fanin -to $cellPins -only_cells]
    set fan_out_gates [all_fanout -from $cellPins -only_cells]
    set gate_list $fan_in_gates
    add_to_collection $gate_list $fan_out_gates
    add_to_collection $gate_list $cellName
    foreach_in_collection gate $gate_list {
      	set_user_attribute [get_cells $gate] P_Gate [computeGateSensitivity $gate]
    }
    set next_sizeable [getNextSizeDown $newlibcellName]
    if {$next_sizeable == "skip"} {
      set S_cells [ remove_from_collection $S_cells $cellName ]
    }
  }

# Find Pmax by sorting cells and looping again
  set S_cells [ sort_collection -descending $S_cells P_Gate ]

  set Pmax [ get_attri [ index_collection $S_cells 0 ] P_Gate ]
  if { $Pmax < 0 } {
    break
  }
  set size [sizeof_collection $S_cells]
  if { $size == 0} {
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
