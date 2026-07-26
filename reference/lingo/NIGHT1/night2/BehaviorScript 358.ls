on mouseUp
  global soundspath, globalnight
  if item 2 of globalnight = "0" then
    sound playFile 1, soundspath & "steal2.aif"
  end if
end
