on mouseUp
  global SaveNames
  x = the clickOn
  repeat with i = 28 to 35
    if i <> (x - 16) then
      sprite(i).visible = 0
      put item i - 27 of SaveNames into field ("save" & i - 27) of castLib 1
      sprite(i + 8).visible = 0
      sprite(i + 8).visible = 1
      member("save" & i - 27).editable = 0
      next repeat
    end if
    sprite(i + 8).visible = 1
    sprite(i).visible = 1
    member("save" & i - 27).editable = 1
    updateStage()
  end repeat
  pass()
end
