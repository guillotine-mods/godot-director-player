on exitFrame
  global afganicnt
  puppetSprite(10, 1)
  puppetSprite(11, 1)
  if afganicnt > 0 then
    set the memberNum of sprite 10 to the number of member "afgan1"
    if afganicnt > 1 then
      set the memberNum of sprite 11 to the number of member "afgan2"
    end if
  end if
end
