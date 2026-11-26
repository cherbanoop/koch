-- N.Y. Noire, шаг 51: игроки скачивают картинки рангов NYPD (po.png, ppo.png, dt*.png, cad.png...)
-- при входе. Если эти иконки уже есть в Workshop-коллекции сервера - не мешает.
for _, f in ipairs(file.Find("materials/ranks_ui/icons/nypd/*.png", "GAME")) do
	resource.AddSingleFile("materials/ranks_ui/icons/nypd/" .. f)
end
