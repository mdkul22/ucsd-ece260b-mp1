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

set cellList [sort_collection [get_cells *] base_name]
set VtswapCnt 0
set SizeswapCnt 0

#my attempt at defining the empty list S
set S [list]
#testing VT comp sense
set SVT [list]

#Mayunk's template CISTA 
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

proc EISTA_GATE_OUT { cellName } {
   set cellPins [ get_pins -of_objects $cellName ]
   set fan_out_cells [ all_fanout -from $cellPins -only_cells ]

   foreach_in_collection fanout_gate $fan_out_cells {
      #query old sensitivity and find new
      set P_OLD_GATE [ get_attri [ get_cells $fanout_gate ] P_Gate ]     
      set P_NEW_GATE [ computeSensitivity $fanout_gate ]

      #if new sense has changed, update it and make recursive call
      if { [ expr $P_NEW_GATE != $P_OLD_GATE ] } {
         set_user_attribute [get_cells $fanout_gate ] P_Gate $P_NEW_GATE
         [ EISTA_GATE_OUT $fanout_gate ]	 
      } 
   }
} 

proc EISTA_VT_OUT { cellName } {
   set cellPins [ get_pins -of_objects $cellName ]
   set fan_out_cells [ all_fanout -from $cellPins -only_cells ]

   foreach_in_collection fanout_gate $fan_out_cells {
      #query old sensitivity and find new
      set P_OLD_VT [ get_attri [ get_cells $fanout_gate ] P_Vt ]     
      set P_NEW_VT [ computeSensitivity $fanout_gate ]

      #if new sense has changed, update it and make recursive call
      if { [ expr $P_NEW_VT != $P_OLD_VT ] } {
         set_user_attribute [get_cells $fanout_gate ] P_Vt $P_NEW_VT
         [ EISTA_VT_OUT $fanout_gate ]	 
      } 
   }   
}

proc EISTA_VT_IN { cellName } {
   set cellPins [ get_pins -of_objects $cellName ]
   set fan_in_cells [ all_fanin -to $cellPins -only_cells ]
   
   foreach_in_collection fanin_gate $fan_in_cells {
      #query old sensitivity and find new
      set P_OLD_VT [ get_attri [ get_cells $fanin_gate ] P_Vt ]     
      set P_NEW_VT [ computeSensitivity $fanin_gate ]

      #if new sense has changed, update it and make recursive call
      if { [ expr $P_NEW_VT != $P_OLD_VT ] } {
         set_user_attribute [get_cells $fanin_gate ] P_Vt $P_NEW_VT
         [ EISTA_VT_IN $fanin_gate ]	 
      } 
   }  
   
}

proc EISTA_GATE_IN { cellName } {
   set cellPins [ get_pins -of_objects $cellName ]
   set fan_in_cells [ all_fanin -to $cellPins -only_cells ]
   
   foreach_in_collection fanin_gate $fan_in_cells {
      #query old sensitivity and find new
      set P_OLD_GATE [ get_attri [ get_cells $fanin_gate ] P_Gate ]     
      set P_NEW_GATE [ computeSensitivity $fanin_gate ]

      #if new sense has changed, update it and make recursive call
      if { [ expr $P_NEW_GATE != $P_OLD_GATE ] } {
         set_user_attribute [get_cells $fanin_gate ] P_Gate $P_NEW_GATE
         [ EISTA_GATE_IN $fanin_gate ]	 
      } 
   }  

}

#find the argument cell's leakage and slack, save state, downsize, CISTA for slack 
#of move (checks immediate fan in and fan out), find leakage, compute sense, then revert state
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
       return [ get_attri [ get_cells $cellName ] P_custom ]
    }
    set newlibcellName [ getNextSizeDown $libcellName ]
    set min_flag [ size_cell  $cellName $newlibcellName ]
    if { [ expr $min_flag == 0 ]  } {
       return [ get_attri [ get_cells $cellName ] P_custom ]
    } 
    update_timing
                  
    #create collection of all fan in cells
    #set fanin [ all_fanin -to $news_size ] 

    #get new info
    set new_slack [ PtCellSlack $cellName ]
    set new_leak  [ PtCellLeak  $cellName ]

    #restore state
    size_cell $cellName $libcellName 

    return [ expr ($old_leak - $new_leak)/($old_slack - $new_slack) ]
}

#compute sensitivity of VT changes
proc computeSensitivityVT { cellName } {
   set old_slack [ PtCellSlack $cellName ]
   set old_leak  [ PtCellLeak  $cellName ]

   set libcell [ get_lib_cells -of_objects $cellName ]
   set libcellName [ get_attri $libcell base_name ]

   #may need check here if Vt is already max?
   if { [ getNextVtDown $libcellName ] == "skip" } {
      return [ get_attri [ get_cells $cellName ] P_custom ]
   }   
   #the getnextVT functions are defined such that up and down refer to 
   #speed, not threshold level.  getNextVtDown actually raises VT, also
   #it returns skip if already an HVT
   set newlibcellName [ getNextVtDown $libcellName ] 
   set max_flag [ size_cell $cellName $newlibcellName ] 
   if { [ expr $max_flag == 0 ] } {
      return [ get_attri [ get_cells $cellName ] P_custom ]
   }
   update_timing

   set new_slack [ PtCellSlack $cellName ]
   set new_leak  [ PtCellLeak $cellName  ]
   
   #restore state   
   size_cell $cellName $libcellName

   return [ expr ($old_leak - $new_leak)/($old_slack - $new_slack) ] 
}

#takes the set S and finds the maximum value within it, returns the 
#max value and its index location
proc findMax {S} {

}

foreach_in_collection cell $cellList {
    set cellName [get_attri $cell base_name]

    # still need these to stop when we get to FF
    set libcell [get_lib_cells -of_objects $cellName]
    set libcellName [get_attri $libcell base_name]
    if {$libcellName == "ms00f80"} {
        continue
    }  
    
    # appends value returned by conputeSensitivity to set list S
    # #passes input parameter cellname to function... $ char allows reading cellname var
    #lappend S [ computeSensitivity $cellName ]
    lappend SVT [ computeSensitivityVT $cellName ]
    #moving printing to outside loop
    #puts [ computeSensitivity $cellName ] 
    
set COMMENTED_OUT {
    #/
    #Vt cell swap example (convert all fast cells (i.e. LVT) to medium cells (i.e. NVT)...
    if { [regexp {[a-z][a-z][0-9][0-9]f[0-9][0-9]} $libcellName] } { 
        set newlibcellName [string replace $libcellName 4 4 m] 
        size_cell $cellName $newlibcellName       
        set newWNS [ PtWorstSlack clk ]
        if { $newWNS < 0.0 } {
            size_cell $cellName $libcellName
        } else {
            incr VtswapCnt
            puts $outFp "- cell ${cellName} is swapped to $newlibcellName"
        }
    }
    #cell size swap example (convert all cells of size 08 to 04)...
    if { [regexp {[a-z][a-z][0-9][0-9][smf]08} $libcellName] } { 
        set newlibcellName [string replace $libcellName 5 6 "04"]
        size_cell $cellName $newlibcellName
        
        set newWNS [ PtWorstSlack clk ]
        if { $newWNS < 0.0 } {
            size_cell $cellName $libcellName
        } else {
            incr SizeswapCnt
            puts $outFp "- cell ${cellName} is swapped to $newlibcellName"
        }
    }
} 

}

#print each sensitivity in S
#foreach i $S {
#    puts $i
#}
#orint SVT sensitivities
foreach i $SVT {
   puts $i
}
#prints total number of cells
puts [sizeof $cellList] 

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


