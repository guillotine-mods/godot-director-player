on mouseUp
  global soundspath
  if sprite(21).visible = 0 then
    sound playFile 1, soundspath & "ware5.aif"
    play frame "dubispk"
  else
    go("waredive")
  end if
end
