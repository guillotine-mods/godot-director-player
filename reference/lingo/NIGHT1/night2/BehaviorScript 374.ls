on exitFrame
  global globalday
  if globalday = 1 then
    go(1, "sleep1.dir")
  else
    go(1, "sleep2.dir")
  end if
end
