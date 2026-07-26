on exitFrame
  global whichsnd, effectspath
  if not soundBusy(2) and (sprite(20).visible = 0) and (sprite(18).visible = 0) and (sprite(36).visible = 0) and (sprite(37).visible = 0) then
    sound playFile 2, effectspath & whichsnd & ".aif"
  end if
  whatodoeveryframe()
  go(marker(0))
end
