on soundspath x
  global soundspath, tlkpath, effectspath, objtlkpath, savepath, soundspathstart
  if the machineType = 256 then
    y = "\"
  else
    y = ":"
  end if
  effectspath = savepath & "fx" & y
  objtlkpath = soundspathstart & "objtlk" & y
  soundspath = soundspathstart & x & y
end

on tlkpath x
  global soundspath, tlkpath, effectspath, savepath, soundspathstart
  if the machineType = 256 then
    y = "\"
  else
    y = ":"
  end if
  effectspath = savepath & "fx" & y
  tlkpath = soundspathstart & x & y
end
