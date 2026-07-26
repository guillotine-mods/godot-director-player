on mouseUp
  global globalday, soundspath
  if globalday = 1 then
    if the memberNum of sprite 11 = the number of member "rotr" then
      set the memberNum of sprite 11 to member("igky").memberNum
    else
      set the memberNum of sprite 11 to the memberNum of sprite 11 + 1
    end if
  else
    if globalday = 2 then
      if the memberNum of sprite 11 = the number of member "prop" then
        set the memberNum of sprite 11 to member("engi").memberNum
      else
        set the memberNum of sprite 11 to the memberNum of sprite 11 + 1
      end if
    else
      if globalday = 3 then
        if the memberNum of sprite 11 = the number of member "joys" then
          set the memberNum of sprite 11 to member("sprn").memberNum
        else
          set the memberNum of sprite 11 to the memberNum of sprite 11 + 1
        end if
      end if
    end if
  end if
  sound playFile 1, soundspath & "artask" & random(5) & ".aif"
end
