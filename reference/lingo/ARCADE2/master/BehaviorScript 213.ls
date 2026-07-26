on exitFrame
  global afganicnt
  afganicnt = value(afganicnt) + 5
  if value(afganicnt) > 72 then
    afganicnt = 72
  end if
  pause()
end
