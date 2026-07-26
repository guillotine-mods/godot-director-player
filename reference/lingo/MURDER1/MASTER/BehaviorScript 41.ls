on exitFrame
  global pptcount, tlkpath
  if pptcount = "1" then
    go("moreof")
    sound playFile 1, tlkpath & "tof11.aif"
  end if
end
