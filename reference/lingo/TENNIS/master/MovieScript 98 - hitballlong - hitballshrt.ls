on hitballlong whatanim
  if (whatanim > 2) and (whatanim < 6) then
    if (the locH of sprite 9 > (the locH of sprite 7 - 80)) and (the locH of sprite 9 < (the locH of sprite 7 + 20)) then
      puppetSprite(9, 1)
      go("hezanswer")
    end if
  end if
end

on hitballshrt whatanim
  if (whatanim > 2) and (whatanim < 6) then
    if (the locH of sprite 9 > (the locH of sprite 7 - 80)) and (the locH of sprite 9 < (the locH of sprite 7 + 20)) then
      puppetSprite(9, 1)
      go("hezanswer")
    end if
  end if
end

on hathitball whatanim
  if (whatanim > 2) and (whatanim < 6) then
    if (the locH of sprite 9 < (the locH of sprite 13 + 80)) and (the locH of sprite 9 > (the locH of sprite 13 - 20)) then
      go("hatanswer")
    end if
  end if
end

on hathitball2 whatanim
  puppetSprite(9, 1)
  go("hatanswer")
end
