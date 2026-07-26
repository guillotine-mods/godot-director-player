on mouseUp
  global soundspath, afganicnt, effectspath, nof
  xxx = "continue"
  afganicnt = afganicnt + 1
  z = 1
  i = 1
  repeat while i <= the number of items in field "shellfield" of castLib "master"
    if (item i of field "shellfield" of castLib "master" = "0") and (xxx = "continue") then
      xxx = "stop"
      put nof into item i of field "shellfield" of castLib "master"
      z = i
    end if
    i = 1 + i
  end repeat
  sound playFile 1, effectspath & "pshell.aif"
  sprite(the clickOn).visible = 0
end
