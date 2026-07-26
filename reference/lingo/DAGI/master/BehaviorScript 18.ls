on exitFrame
  global freeforall
  freeforall = freeforall + 1
  if freeforall > 1 then
    go("choose1abc")
  else
    go("choose1")
  end if
end
