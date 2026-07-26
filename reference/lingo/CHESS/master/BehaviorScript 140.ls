on mouseUp
  global globalday, soundspath
  if globalday = 1 then
    if the memberNum of sprite 11 = the number of member "igky" then
      set the memberNum of sprite 11 to member("rotr").memberNum
    else
      set the memberNum of sprite 11 to the memberNum of sprite 11 - 1
    end if
  else
    if globalday = 2 then
      if the memberNum of sprite 11 = the number of member "engi" then
        set the memberNum of sprite 11 to member("prop").memberNum
      else
        set the memberNum of sprite 11 to the memberNum of sprite 11 - 1
      end if
    else
      if globalday = 3 then
        if the memberNum of sprite 11 = the number of member "sprn" then
          set the memberNum of sprite 11 to member("joys").memberNum
        else
          set the memberNum of sprite 11 to the memberNum of sprite 11 - 1
        end if
      end if
    end if
  end if
  sound playFile 1, soundspath & "artask" & random(5) & ".aif"
end
