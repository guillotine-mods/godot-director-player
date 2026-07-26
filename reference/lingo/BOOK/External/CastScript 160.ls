on mouseUp
  global effectspath
  sound playFile 1, effectspath & "page.aif"
  go(the frame - 1)
end
