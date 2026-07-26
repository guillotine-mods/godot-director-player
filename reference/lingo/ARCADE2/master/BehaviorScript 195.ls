on exitFrame
  global soundspath
  if (the memberNum of sprite 7 <> the number of member "action1") and (the memberNum of sprite 7 <> the number of member "aii") then
    set the memberNum of sprite 7 to the number of member "aii"
    zigi = 3
    put value(the text of field "score") - 1 into field "score"
    if value(the text of field "score") = 0 then
      sound playFile 1, soundspath & "zigidead.aif"
      repeat with i = 3 to 15
        set the visible of sprite i to 1
      end repeat
      go("gameover")
    else
      set the memberNum of sprite 40 to the number of member ("zigi" & value(the text of field "score"))
      sound playFile 1, soundspath & "zigiaii.aif"
    end if
  end if
end
