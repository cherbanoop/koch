-- "addons\\mc_phone\\lua\\mc_phone\\extentions\\sv_ep1_noire.lua"
--[[---------------------------------------------------------------------------
DLC #1 - сигнал сети (восстановлено, шаг 20). Клиент: cl_ep1_init.lua (McPhone.SignalChange Int3, McPhone.NoSignal).
  Сигнал 0-3: вышки mc_antenna (TowerMaxRange: ближняя треть - 3, вторая - 2, дальняя - 1, дальше - 0).
  Если на карте нет ни одной вышки - сигнал везде полный (3). Все вышки сломаны - сигнала нет.
  Глушилка mc_jammer (оружие mcw_jammer ставит её на стену) - в радиусе JammerRange сигнала нет.
  Зоны без сигнала: McPhone.Config.ZonesDLC[карта] = {{Vector, Vector}, ...} (коробки).
  Вышки: меню телефона (суперадмин) -> настройки -> вышки: "Сохранить" / "Поставить" / "Убрать все".
  Хранятся в data/<ServerID>/towers_<карта>.txt, ставятся при старте карты и после очистки.
---------------------------------------------------------------------------]]
McPhone.EP1.Enabled = true

local function towersFile()
	return McPhone.ServerID .. "/towers_" .. game.GetMap() .. ".txt"
end

function McPhone.EP1.SpawnTower(pos, ang)
	local ent = ents.Create("mc_antenna")
	if not IsValid(ent) then return end

	ent:SetPos(pos)
	ent:SetAngles(ang or angle_zero)
	ent:Spawn()
	ent:Activate()

	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(false) end

	ent.McPhoneSaved = true

	return ent
end

function McPhone.EP1.LoadTowers()
	if not file.Exists(towersFile(), "DATA") then return end

	local data = util.JSONToTable(file.Read(towersFile(), "DATA") or "") or {}

	for _, ent in ipairs(ents.FindByClass("mc_antenna")) do
		if ent.McPhoneSaved then ent:Remove() end
	end

	for _, v in ipairs(data) do
		if isvector(v.pos) then McPhone.EP1.SpawnTower(v.pos, v.ang) end
	end

	MsgC(Color(0, 255, 0), "[McPhone] towers loaded: " .. #data .. "\n")
end

function McPhone.EP1.SaveTowers()
	local data = {}

	for _, ent in ipairs(ents.FindByClass("mc_antenna")) do
		table.insert(data, {pos = ent:GetPos(), ang = ent:GetAngles()})
		ent.McPhoneSaved = true
	end

	file.Write(towersFile(), util.TableToJSON(data, true))

	return #data
end

hook.Add("InitPostEntity", "McPhone.EP1.Towers", function()
	timer.Simple(2, McPhone.EP1.LoadTowers)
end)

hook.Add("PostCleanupMap", "McPhone.EP1.Towers", function()
	timer.Simple(1, McPhone.EP1.LoadTowers)
end)

local function admin(ply)
	return IsValid(ply) and ply:IsSuperAdmin()
end

net.Receive("McPhone.SaveTowers", function(_, ply)
	if not admin(ply) then return end

	local n = McPhone.EP1.SaveTowers()
	McPhone.DefaultNotify(ply, 0, 5, "Вышки связи сохранены: " .. n)
end)

net.Receive("McPhone.SpawnTower", function(_, ply)
	if not admin(ply) then return end

	local tr = ply:GetEyeTrace()
	local ent = McPhone.EP1.SpawnTower(tr.HitPos, Angle(0, ply:EyeAngles().y + 180, 0))

	if IsValid(ent) then
		ent.McPhoneSaved = nil
		if ent.CPPISetOwner then ent:CPPISetOwner(ply) end
		undo.Create("Cell tower")
			undo.AddEntity(ent)
			undo.SetPlayer(ply)
		undo.Finish()
		McPhone.DefaultNotify(ply, 0, 5, "Вышка поставлена. Не забудьте сохранить вышки")
	end
end)

net.Receive("McPhone.RemoveTowers", function(_, ply)
	if not admin(ply) then return end

	for _, ent in ipairs(ents.FindByClass("mc_antenna")) do
		ent:Remove()
	end

	McPhone.DefaultNotify(ply, 0, 5, "Все вышки убраны (сохраните, чтобы не вернулись после рестарта)")
end)

--[[---------------------------------------------------------------------------
Сигнал
---------------------------------------------------------------------------]]
function McPhone.EP1.CalcSignal(ply)
	local pos = ply:GetPos()

	for _, jam in ipairs(McPhone.EP1.Jammers) do
		if IsValid(jam) and jam:GetActive() and jam:GetPos():DistToSqr(pos) <= McPhone.Config.JammerRange ^ 2 then
			return 0
		end
	end

	local zones = McPhone.Config.ZonesDLC and McPhone.Config.ZonesDLC[game.GetMap()]

	if istable(zones) then
		for _, z in ipairs(zones) do
			if isvector(z[1]) and isvector(z[2]) and McPhone.IsPlayerInBox(ply, z[1], z[2]) then return 0 end
		end
	end

	if not McPhone.Config.TowerRangebasedNet then return 3 end

	local any, best = false, math.huge

	for _, tower in ipairs(McPhone.EP1.Towers) do
		if not IsValid(tower) then continue end
		any = true

		if tower:GetDestroyed() then continue end

		local d = tower:GetPos():DistToSqr(pos)
		if d < best then best = d end
	end

	if not any then return 3 end
	if best == math.huge then return 0 end

	local range = McPhone.Config.TowerMaxRange
	best = math.sqrt(best)

	if best <= range / 3 then return 3 end
	if best <= range / 3 * 2 then return 2 end
	if best <= range then return 1 end

	return 0
end

timer.Create("McPhone.EP1.Signal", 1, 0, function()
	local now = CurTime()

	-- ремонт вышек и срок жизни глушилок
	for _, tower in ipairs(McPhone.EP1.Towers) do
		if not IsValid(tower) then continue end

		if tower:GetDestroyed() then
			if tower.DestroyTime and tower.DestroyTime < now then tower:Repair() end
		elseif tower:GetDamageLimit() < McPhone.Config.TowerHealth and tower.DamageTime and tower.DamageTime < now then
			tower:Repair()
		end
	end

	for _, jam in ipairs(McPhone.EP1.Jammers) do
		if IsValid(jam) and jam:GetActive() and jam.LiveTime and jam.LiveTime < now then
			jam:BreakJammer()
		end
	end

	for _, ply in ipairs(player.GetAll()) do
		local signal = McPhone.EP1.CalcSignal(ply)

		if ply.McPhoneSignal ~= signal then
			ply.McPhoneSignal = signal

			if not ply:IsBot() then
				net.Start("McPhone.SignalChange")
					net.WriteInt(signal, 3)
				net.Send(ply)
			end

			-- пропал сигнал - звонок обрывается (таксофон работает по проводу)
			if signal < 1 and not IsValid(ply.McPayPhone) and (IsValid(ply.McPhoneOnCall) or IsValid(ply.McPhoneCalling) or IsValid(ply.McPhoneInCall)) then
				McPhone.EndCall(ply)

				net.Start("McPhone.NoSignal")
				net.Send(ply)
			end
		end
	end
end)

-- новый игрок: -1 - чтобы первый же тик отправил ему настоящий сигнал (клиент стартует с 0)
hook.Add("PlayerInitialSpawn", "McPhone.EP1.Signal", function(ply)
	ply.McPhoneSignal = -1
end)
