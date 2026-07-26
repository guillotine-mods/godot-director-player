on tlkpath x
  global soundspath, tlkpath, effectspath, soundspathstart
  if the machineType = 256 then
    y = "\"
  else
    y = ":"
  end if
  effectspath = the moviePath & "fx" & y
  tlkpath = soundspathstart & x & y
  soundspath = soundspathstart & x & y
end
