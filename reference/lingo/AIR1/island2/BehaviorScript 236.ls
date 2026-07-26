on mouseUp
  global soundspath
  y = 10
  repeat with i = 1 to 10
    if line i of field "plane" of castLib "master" = "empty" then
      y = y - 1
    end if
  end repeat
  soundspath("air")
  sound playFile 1, soundspath & "misin" & y & ".aif"
end
