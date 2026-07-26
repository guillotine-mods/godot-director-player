on exitFrame
  global effectspath, whichsnd
  if whichsnd <> "cats" then
    sound playFile 2, effectspath & "church2.aif"
    whichsnd = "clif1"
  else
    sound playFile 2, effectspath & "clif1.aif"
    whichsnd = "clif1"
  end if
end
