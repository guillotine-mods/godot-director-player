on exitFrame
  global effectspath, whichsnd
  if sprite(7).visible = 1 then
    if not soundBusy(2) or (whichsnd <> "lgtbrk") then
      sound playFile 2, effectspath & "lgtbrk.aif"
      whichsnd = "lgtbrk"
    end if
  else
    if not soundBusy(2) or (whichsnd <> "lgteng") then
      sound playFile 2, effectspath & "lgteng.aif"
      whichsnd = "lgteng"
    end if
  end if
end
