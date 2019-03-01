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
      {(^.*\/[a-zA-Z]) .* +\(VIOLATED} {
          regexp {(^.*\/[a-zA-Z]) .* +\(VIOLATED} $line full pin
              lappend capVioPins $pin
              continue
      }
    }
  }

  close $REPORT_FILE
    return $capVioPins
}
# calculates Vt Sensitivity
proc computeSensitivityVT { cellName } {
   set cellPins [ get_pins -of_objects $cellName ]
   set pout [ all_fanout -from $cellPins ]
   set old_paths [ get_timing_paths -through $pout ]
   set old_pns 0
   foreach_in_collection path $old_paths {
      set old_pns [ expr $old_pns + [ get_attri $path slack ] ]
   }

   #set old_slack [ PtCellSlack $cellName ]
   set old_leak  [ PtCellLeak  $cellName ]

   set libcell [ get_lib_cells -of_objects $cellName ]
   set libcellName [ get_attri $libcell base_name ]

   #may need check here if Vt is already max?
   if { [ getNextVtDown $libcellName ] == "skip" } {
      return 0
   }
   #the getnextVT functions are defined such that up and down refer to
   #speed, not threshold level.  getNextVtDown actually raises VT, also
   #it returns skip if already an HVT
   set newlibcellName [ getNextVtDown $libcellName ]
   set max_flag [ size_cell $cellName $newlibcellName ]
   if { [ expr $max_flag == 0 ] } {
      return 0
   }

   set cellPins [ get_pins -of_objects $newlibcellName ]
   set pout [ all_fanout -from $cellPins ]
   set new_paths [ get_timing_paths -through $pout ]
   set new_pns 0
   foreach_in_collection path $new_paths {
      set new_pns [ expr $new_pns + [ get_attri $path slack ] ]
   }
   #set new_slack [ PtCellSlack $cellName ]
   set new_leak  [ PtCellLeak $cellName  ]

   #restore state
   size_cell $cellName $libcellName

   set sense [ expr ($old_leak - $new_leak)/($old_pns - $new_pns) ]
   puts "Computed Vt sensitivity $sense"
   return $sense
}
# calculates gate sensitivity
proc computeGateSensitivity { cellName } {
    set cellPins [ get_pins -of_objects $cellName ]
    set pout [ all_fanout -from $cellPins ]
    set old_paths [ get_timing_paths -through $pout ]
    set old_pns 0
    foreach_in_collection path $old_paths {
       set old_pns [ expr $old_pns + [ get_attri $path slack ] ]
    }

    #set old_slack [ PtCellSlack $cellName ]
    set old_leak  [ PtCellLeak  $cellName ]

    set libcell [ get_lib_cells -of_objects $cellName ]
    set libcellName [ get_attri $libcell base_name ]

    # may need check here if Gate is already min?
    if { [ getNextSizeDown $libcellName ] == "skip" } {
       return 0
    }
    set newlibcellName [ getNextSizeDown $libcellName ]
    set max_flag [ size_cell $cellName $newlibcellName ]
    if { [ expr $max_flag == 0 ] } {
       return 0
    }

    set cellPins [ get_pins -of_objects $newlibcellName ]
    set pout [ all_fanout -from $cellPins ]
    set new_paths [ get_timing_paths -through $pout ]
    set new_pns 0
    foreach_in_collection path $new_paths {
       set new_pns [ expr $new_pns + [ get_attri $path slack ] ]
    }
    #set new_slack [ PtCellSlack $cellName ]
    set new_leak  [ PtCellLeak $cellName  ]

    #restore state
    size_cell $cellName $libcellName

    set sense [ expr ($old_leak - $new_leak)/($old_pns - $new_pns) ]
    puts "Computed Sizing sensitivity $sense"
    return $sense
}

# P_Gate and P_Vt sensitivity calculations
set count 0
foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    # set minimum to zero
    if {$libcellName == "ms00f80"} {
        incr count
        continue
    }
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
    set_user_attribute [get_cells $cellName] P_Gate 0
    set_user_attribute [get_cells $cellName] P_Gate [computeGateSensitivity $cellName]
    set_user_attribute [get_cells $cellName] P_Vt 0
    set_user_attribute [get_cells $cellName] P_Vt [computeSensitivityVT $cellName]
    incr count
    puts "First loop: assigned sensitivity to cell #$count"
}

puts "\ndone with first loop\n"

set S_cells []
set S_cells [ sort_collection -descending [get_cells *] P_Vt ]


# remove registers for both the lists
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
  } else {
    puts "Second loop: $size cells left in collection"
  }
  # removing value Pmax from List
  #set S_cells [remove_from_collection $S_cells $cellName]
  if {$libcellName == "ms00f80"} {
      continue
  }
  set Pcell [ get_attri [ index_collection $S_cells 0 ] P_Vt ]
  if {$Pcell == 0} {
    set S_cells [ remove_from_collection $S_cells $cell ]
    continue
  }
  set newlibcellName1 [ getNextVtDown $libcellName ]
  set newlibcellName2 [ getNextVtDown $newlibcellName1 ]
  #check if sizeable, if not remove from list
  if { {$newlibcellName2} != "skip"} {
  set sizeable [size_cell $cellName $newlibcellName2 ]
  # doing incremental timing of all cell paths to ensure no faults
  update_timing
  set new_wns [ PtWorstSlack clk ]
  } else {
  set sizeable [size_cell $cellName $newlibcellName1 ]
  # doing incremental timing of all cell paths to ensure no faults
  update_timing
  set new_wns [ PtWorstSlack clk ]
  }
  if {$new_wns < 1 && {$newlibcellName2} != "skip"} {
    set sizeable [size_cell $cellName $newlibcellName1 ]
    update_timing
    set new_wns [ PtWorstSlack clk ]
  }

  if {$new_wns < 1 || $sizeable == 0} {
    size_cell $cellName $libcellName
    set S_cells [ remove_from_collection $S_cells $cell ]
    continue
  }
  #location for incrementing vt swaps
    #set cellPins [get_pins -of_objects $cellName]
    #set fan_in_gates [all_fanin -to $cellPins -only_cells]
    #set fan_out_gates [all_fanout -from $cellPins -only_cells]
    #set gate_list $fan_in_gates
    #add_to_collection $gate_list $fan_out_gates
    #add_to_collection $gate_list $cellName
    #foreach_in_collection gate $gate_list {
    #  	set_user_attribute [get_cells $gate] P_Vt [computeSensitivityVT $gate]
    #}
    incr VtswapCnt
    set S_cells [ remove_from_collection $S_cells $cell]
  # Find Pmax by sorting cells and looping again

  set Pmax [ get_attri [ index_collection $S_cells 0 ] P_Vt ]
  if { $Pmax < 0 } {
    break
  }
}

set G_cells []
set G_cells [ sort_collection -descending [get_cells *] P_Gate ]

foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {$libcellName == "ms00f80"} {
      set G_cells [remove_from_collection $G_cells $cell]
    }
    if { [regexp {[a-z][a-z]01[smf][0-9][0-9]} $libcellName] } {
      set G_cells [remove_from_collection $G_cells $cell]
    }
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
}
set Pmax [ get_attri [ index_collection $G_cells 0 ] P_Gate ]
puts "Pmax is $Pmax"
while {  $Pmax > 0.0 } {
  # get max value and iterator to get cell from collection
  set cell [ index_collection $G_cells 0 ]
  set cellName [get_attri $cell base_name]
  set libcell [get_lib_cells -of_objects $cellName]
  set libcellName [get_attri $libcell base_name]
  set size [sizeof_collection $G_cells]
  if { $size == 0} {
    break
  } else {
    puts "3rd loop: $size cells left in collection"
  }
  # removing value Pmax from List
  #set G_cells [remove_from_collection $G_cells $cellName]
  if {$libcellName == "ms00f80"} {
      continue
  }
  set Pcell [ get_attri [ index_collection $G_cells 0 ] P_Gate ]
  if {$Pcell == 0} {
    set G_cells [ remove_from_collection $G_cells $cell ]
    continue
  }
  set newlibcellName1 [ getNextSizeDown $libcellName ]
  set newlibcellName2 [ getNextSizeDown $newlibcellName1 ]
  #check if sizeable, if not remove from list
  if { {$newlibcellName2} != "skip"} {
  set sizeable [size_cell $cellName $newlibcellName2 ]
  # doing incremental timing of all cell paths to ensure no faults
  update_timing
  set new_wns [ PtWorstSlack clk ]
  } else {
  set sizeable [size_cell $cellName $newlibcellName1 ]
  # doing incremental timing of all cell paths to ensure no faults
  update_timing
  set new_wns [ PtWorstSlack clk ]
  }
  if {$new_wns < 0.5 && {$newlibcellName2} != "skip"} {
    set sizeable [size_cell $cellName $newlibcellName1 ]
    update_timing
    set new_wns [ PtWorstSlack clk ]
  }

  if {$new_wns < 0.5 || $sizeable == 0} {
    size_cell $cellName $libcellName
    set G_cells [ remove_from_collection $G_cells $cell ]
    continue
  }
  #location for incrementing gate swaps

    #set gate_list $fan_in_gates
    #add_to_collection $gate_list $fan_out_gates
    #add_to_collection $gate_list $cellName
    #foreach_in_collection gate $gate_list {
    #  	set_user_attribute [get_cells $gate] P_Vt [computeSensitivityVT $gate]
    #}
    incr SizeswapCnt
    set G_cells [ remove_from_collection $G_cells $cell ]
  set Pmax [ get_attri [ index_collection $G_cells 0 ] P_Gate ]
  if { $Pmax < 0 } {
    break
  }
}

set val [ PtGetCapVio ]
set vioPins [GetCapVPins]
set violations [llength $vioPins]

foreach pin $vioPins {
  set source_cell [get_cells -of_objects [get_pins $pin]]
  set fan_out_gates [all_fanout -from [get_pins $pin] -only_cells]
  foreach_in_collection fcell $fan_out_gates {
    if {$libcellName == "ms00f80"} {
        continue
    }
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
#set S_cells []
#set S_cells [ sort_collection -descending [get_cells *] P_Gate ]
#foreach_in_collection cell $cellList {
#    set cellName [get_attri $cell base_name]
#    set libcell [get_lib_cells -of_objects $cellName]
#    set libcellName [get_attri $libcell base_name]
#    if {$libcellName == "ms00f80"} {
#      set S_cells [remove_from_collection $S_cells $cell]
#    }
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
#}

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
