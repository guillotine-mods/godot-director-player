on mouseUp
  global effectspath, cdsavepath
  sound playFile 1, effectspath & "clik3.aif"
  forget(window(cdsavepath & "saveload.dxr"))
end
