on exitFrame
  global zigi, soundspath
  zigi = zigi - 1
  if zigi = 0 then
    set the memberNum of sprite 7 to the number of member "zigidefault" of castLib 1
    updateStage()
  end if
  if (the memberNum of sprite 7 = the number of member "action2") or (the memberNum of sprite 7 <= the number of member "action3") then
    repeat with i = 8 to 12
      if (sprite 7 intersects i and (sprite(i).visible = 1)) or (sprite(i + 15).visible = 1) then
        if not soundBusy(3) then
          sound playFile 3, soundspath & "foe" & random(5) & ".aif"
        end if
        sprite(i).visible = 0
        sprite(i + 15).visible = 1
        next repeat
      end if
      sprite(i + 15).visible = 0
    end repeat
  end if
end
