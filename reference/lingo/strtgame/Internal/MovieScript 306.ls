on gomenu
  when keyDown then go to "mainmenub4"
end

on fromnow
  if the keyCode = "49" then
    sound stop 1
  else
    nothing()
  end if
end

on gomenu2
  when keyDown then gulu
end

on gulu
  set the keyDownScript to "fromnow"
  go("mainmenub4")
end
