on exitFrame
  global whichsnd, effectspath
  if not soundBusy(2) then
    sound playFile 2, effectspath & whichsnd & ".aif"
  end if
  whatodoeveryframe()
  go(marker(0))
end
