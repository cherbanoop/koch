-- "addons\\mc_phone\\lua\\mc_phone\\extentions\\sv_noire_web.lua"
--[[---------------------------------------------------------------------------
McPhone 1.2.0 (N.Y. Noire) - сервер для сайтов телефона и таксофонов (восстановлено по клиенту, шаг 20).
  SkyLine Риелтор (modules/web_properly.lua, GPS):
    territorySendInfo  кл -> сер: пусто; сер -> кл: Table {[имя] = {masterOwner, propetytype}}
                       (свободная недвижимость и своя; чужой в списке нет)
    territoryBuy / territorySell        кл -> сер: String имя
    territoryAddOwner / territoryRemoveOwner  кл -> сер: String имя, Entity игрок
  Контракты на оружие (modules/web_shop_gun.lua, сайт "rdm"):
    DarkRP.ShareDataReq  кл -> сер: UInt3 0; сер -> кл: UInt3 0, Bool есть, [Table {name, weapon = {class, ammount}, price}]
    Сдать оружие по контракту: прийти на точку сбыта (метка GPS на сайте) и написать /sellguns.
  Таксофоны mc_payphone (невидимая пластина на модели таксофона карты):
    поставить из Q-меню (McPhone -> PayPhone), noire_payphones_save - сохранить, noire_payphones_load - вернуть.
  Магазины (web_shop, web_shop_junk, web_shop_gun, web_gov) покупают через DarkRP.PlayerBuyItem (гейммод).
---------------------------------------------------------------------------]]
for _, str in ipairs({"territorySendInfo", "territoryBuy", "territorySell", "territoryAddOwner", "territoryRemoveOwner", "DarkRP.ShareDataReq"}) do
	util.AddNetworkString(str)
end

local function delay(ply, name, t)
	return DarkRP and DarkRP.NetDelay and DarkRP.NetDelay(ply, name, t)
end

--[[---------------------------------------------------------------------------
Недвижимость
---------------------------------------------------------------------------]]
function McPhone.TerritoryList(ply)
	local res = {}
	if not Territories or not Territories.list then return res end

	for name, t in pairs(Territories.list) do
		if not t.buyable then continue end

		local owner = t.masterOwner

		if IsValid(owner) then
			if owner == ply then
				res[name] = {masterOwner = owner, propetytype = t.propetytype}
			end
		elseif not t:Owned() then
			res[name] = {}
		end
	end

	return res
end

function McPhone.SendTerritories(ply)
	if not IsValid(ply) then return end

	net.Start("territorySendInfo")
		net.WriteTable(McPhone.TerritoryList(ply))
	net.Send(ply)
end

local function getTerritory(ply)
	local t = Territories and Territories.list and Territories.list[net.ReadString()]
	if not t or not t.buyable then return end

	return t
end

local function refresh(ply)
	if TerritoriesInfoUpdate then TerritoriesInfoUpdate() end

	timer.Simple(0.5, function()
		if IsValid(ply) then McPhone.SendTerritories(ply) end
	end)
end

net.Receive("territorySendInfo", function(_, ply)
	if delay(ply, "territorySendInfo", 1) then return end

	McPhone.SendTerritories(ply)
end)

net.Receive("territoryBuy", function(_, ply)
	if delay(ply, "territoryBuy", 2) then return end

	local t = getTerritory(ply)
	if not t or not McPhone.CanUsePhone(ply) then return end

	if t:Owned() then
		DarkRP.notify(ply, 1, 4, "Эта недвижимость уже занята")
		McPhone.SendTerritories(ply)
		return
	end

	if McPhone.GetSignal(ply) < 1 then
		DarkRP.notify(ply, 1, 4, "Нет сигнала сети")
		return
	end

	if hook.Run("DarkRP.CanBuyProperty", ply, t) == false then return end

	t:OnBuy(ply)

	if t.masterOwner == ply then
		DarkRP.notify(ply, 0, 5, "Вы арендовали: " .. (t.printName or t.name))
	end

	refresh(ply)
end)

net.Receive("territorySell", function(_, ply)
	if delay(ply, "territorySell", 2) then return end

	local t = getTerritory(ply)
	if not t or not ply:IsTerritoryMasterOwner(t) then return end

	t:OnSell(ply)
	refresh(ply)
end)

net.Receive("territoryAddOwner", function(_, ply)
	if delay(ply, "territoryAddOwner", 1) then return end

	local t = getTerritory(ply)
	local target = net.ReadEntity()
	if not t or not ply:IsTerritoryMasterOwner(t) then return end

	if not IsValid(target) or not target:IsPlayer() or target == ply then
		DarkRP.notify(ply, 1, 4, "Игрок не найден (он должен быть в городе)")
		return
	end

	if t.extraOwners and t.extraOwners[target:AccountID()] then
		DarkRP.notify(ply, 1, 4, target:Nick() .. " уже совладелец")
		return
	end

	t.extraOwners = t.extraOwners or {}
	t:AddOwner(target)
	DarkRP.notify(ply, 0, 4, target:Nick() .. " получил доступ к " .. (t.printName or t.name))
	DarkRP.log("property", ply, target, "выдал доступ к недвижимости [" .. t.name .. "]")
	refresh(ply)
end)

net.Receive("territoryRemoveOwner", function(_, ply)
	if delay(ply, "territoryRemoveOwner", 1) then return end

	local t = getTerritory(ply)
	local target = net.ReadEntity()
	if not t or not ply:IsTerritoryMasterOwner(t) or not IsValid(target) or not target:IsPlayer() then return end

	if not t.extraOwners or not t.extraOwners[target:AccountID()] then
		DarkRP.notify(ply, 1, 4, target:Nick() .. " не совладелец")
		return
	end

	t:RemoveOwner(target)
	DarkRP.notify(ply, 0, 4, target:Nick() .. " больше не имеет доступа")
	DarkRP.log("property", ply, target, "забрал доступ к недвижимости [" .. t.name .. "]")
	refresh(ply)
end)

--[[---------------------------------------------------------------------------
Контракты на оружие ("Подходящий контракт" на сайте оружейного магазина)
---------------------------------------------------------------------------]]
McPhone.GunContracts = McPhone.GunContracts or {}

local GC = {
	Points = {Vector(679.38, -5573.25, -319.63)}, -- точки сбыта (первая - метка GPS на сайте)
	Radius = 250,
	Lifetime = {2400, 3600}, -- сколько живёт контракт, сек
	Pause = {600, 1200}, -- пауза после выполнения квоты
	Amount = {2, 5}, -- минимум штук за одну сдачу
	Quota = {6, 15}, -- общая квота контракта
	Premium = {10, 40}, -- премия к цене оружия, %
	Names = {"Сальваторе Мартелли", "Братья Ди Карло", "Мистер Флинн", "Шон О'Мэлли", "Дон Витторио", "Гарри Шульц", "Ричи Кастелло"},
}

McPhone.GunContracts.Config = GC

local function weaponPrice(class)
	local w = DarkRP.Weapons and DarkRP.Weapons[class]
	return w and (w.price or w.pricesep) or 0
end

function McPhone.GunContracts.New()
	local list = {}

	for class in pairs(GunNamesGlobal or {}) do
		if weaponPrice(class) > 0 then table.insert(list, class) end
	end

	if #list == 0 then
		McPhone.GunContracts.Active = nil
		return
	end

	local amount = math.random(GC.Amount[1], GC.Amount[2])

	McPhone.GunContracts.Active = {
		name = GC.Names[math.random(#GC.Names)],
		weapon = {class = list[math.random(#list)], ammount = amount},
		price = math.random(GC.Premium[1], GC.Premium[2]),
		quota = math.max(amount, math.random(GC.Quota[1], GC.Quota[2])),
		sold = 0,
		expires = CurTime() + math.random(GC.Lifetime[1], GC.Lifetime[2]),
	}

	return McPhone.GunContracts.Active
end

function McPhone.GunContracts.Get()
	local c = McPhone.GunContracts.Active

	if c and c.expires < CurTime() then
		c = nil
		McPhone.GunContracts.Active = nil
	end

	if not c and (McPhone.GunContracts.NextTime or 0) < CurTime() then
		c = McPhone.GunContracts.New()
	end

	return c
end

net.Receive("DarkRP.ShareDataReq", function(_, ply)
	if delay(ply, "DarkRP.ShareDataReq", 1) then return end

	local id = net.ReadUInt(3)
	if id ~= 0 then return end

	local c = McPhone.GunContracts.Get()

	net.Start("DarkRP.ShareDataReq")
		net.WriteUInt(0, 3)
		net.WriteBool(c ~= nil)
		if c then
			net.WriteTable({name = c.name, weapon = {class = c.weapon.class, ammount = c.weapon.ammount}, price = c.price})
		end
	net.Send(ply)
end)

local function nearPoint(ply)
	local pos = ply:GetPos()

	for _, p in ipairs(GC.Points) do
		if p:DistToSqr(pos) <= GC.Radius ^ 2 then return true end
	end
end

local function sellGuns(ply)
	local c = McPhone.GunContracts.Get()

	if not c then
		DarkRP.notify(ply, 1, 5, "Сейчас нет открытых контрактов")
		return ""
	end

	if not nearPoint(ply) then
		DarkRP.notify(ply, 1, 5, "Оружие по контракту принимают только на точке сбыта (метка на сайте)")
		return ""
	end

	local inv = ply.inv and ply.inv[INV_WEAPON]
	if not inv then return "" end

	local found, noserial = {}, 0

	for i, item in ipairs(inv) do
		if item.class ~= c.weapon.class then continue end

		if istable(item.register) and item.register.id then
			table.insert(found, i)
		else
			noserial = noserial + 1
		end
	end

	local wname = DarkRP.Weapons[c.weapon.class] and DarkRP.Weapons[c.weapon.class].name or c.weapon.class

	if #found < c.weapon.ammount then
		DarkRP.notify(ply, 1, 6, "Нужно минимум " .. c.weapon.ammount .. " шт. (" .. wname .. ") с серийным номером, у вас " .. #found .. (noserial > 0 and (", без номера не берём: " .. noserial) or ""))
		return ""
	end

	local count = math.min(#found, c.quota - c.sold)
	local each = math.floor(weaponPrice(c.weapon.class) * (1 + c.price / 100))
	local total = each * count

	for n = count, 1, -1 do
		table.remove(inv, found[n])
	end

	ply:addMoney(total)
	c.sold = c.sold + count

	McINV.Send(ply)
	DarkRP.notify(ply, 0, 6, "Контракт " .. c.name .. ": сдано " .. count .. " шт. (" .. wname .. ") на $" .. string.Comma(total))
	DarkRP.log("other", ply, nil, "сдал по контракту " .. count .. " шт. [" .. c.weapon.class .. "] за $" .. total)

	if c.sold >= c.quota then
		McPhone.GunContracts.Active = nil
		McPhone.GunContracts.NextTime = CurTime() + math.random(GC.Pause[1], GC.Pause[2])
		McPhone.NewMail(c.name, "Квота по контракту закрыта. Спасибо за сотрудничество - следите за новыми заказами.", ply)
	end

	return ""
end

local function addCommands()
	if not DarkRP or not DarkRP.defineChatCommand then return end

	DarkRP.defineChatCommand("sellguns", sellGuns, 2)
end

hook.Add("DarkRPFinishedLoading", "McPhone.GunContracts", addCommands)
if DarkRP and DarkRP.defineChatCommand and GAMEMODE then addCommands() end

--[[---------------------------------------------------------------------------
Таксофоны: сохранение позиций
---------------------------------------------------------------------------]]
local function payFile()
	return McPhone.ServerID .. "/payphones_" .. game.GetMap() .. ".txt"
end

function McPhone.LoadPayPhones()
	if not file.Exists(payFile(), "DATA") then return end

	local data = util.JSONToTable(file.Read(payFile(), "DATA") or "") or {}

	for _, ent in ipairs(ents.FindByClass("mc_payphone")) do
		if ent.McPhoneSaved then ent:Remove() end
	end

	for _, v in ipairs(data) do
		if not isvector(v.pos) then continue end

		local ent = ents.Create("mc_payphone")
		if not IsValid(ent) then return end

		ent:SetPos(v.pos)
		ent:SetAngles(v.ang or angle_zero)
		ent:Spawn()
		ent:SetNumber(v.num or "")
		ent.McPhoneSaved = true

		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end

	MsgC(Color(0, 255, 0), "[McPhone] payphones loaded: " .. #data .. "\n")
end

hook.Add("InitPostEntity", "McPhone.PayPhones", function()
	timer.Simple(2, McPhone.LoadPayPhones)
end)

hook.Add("PostCleanupMap", "McPhone.PayPhones", function()
	timer.Simple(1, McPhone.LoadPayPhones)
end)

concommand.Add("noire_payphones_save", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end

	local data = {}

	for _, ent in ipairs(ents.FindByClass("mc_payphone")) do
		table.insert(data, {pos = ent:GetPos(), ang = ent:GetAngles(), num = ent:GetNumber()})
		ent.McPhoneSaved = true
	end

	file.Write(payFile(), util.TableToJSON(data, true))

	local msg = "[McPhone] сохранено таксофонов: " .. #data
	if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end)

concommand.Add("noire_payphones_load", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end

	McPhone.LoadPayPhones()
end)
