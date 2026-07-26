on exitFrame
  global zigi, soundspath
  zigi = zigi - 1
  if zigi = 0 then
    set the memberNum of sprite 7 to the number of member "zigidefault" of castLib 1
    updateStage()
  end if
  repeat with i = 8 to 15
    if sprite i intersects 7 and (the visible of sprite i <> 0) then
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
          next repeat
        end if
        set the memberNum of sprite 40 to the number of member ("zigi" & value(the text of field "score"))
        sound playFile 1, soundspath & "zigiaii.aif"
      end if
    end if
  end repeat
end
