--[[
	TrackIR for GMod (extended version)

	Client console commands:
		trackir_enabled 0/1    - master switch for the whole plugin
		trackir_autoenable 0/1 - turn on by itself when a TrackIR device is found,
		                         turn off when it isn't
		trackir_toggle         - flip the master switch
		trackir_recheck        - look for the device again, right now
		trackir_center         - use the current head position as the center
		trackir_reset          - put every setting back to its default
		trackir_status         - print module info (version / status / debug) to the console
		trackir_debug 0/1      - print what the device detection sees (for troubleshooting)
		trackir_camera_mode    - 0: ignore TrackIR while looking through a camera (default),
		                         1: apply TrackIR on top of the camera view
		trackir_chain 0/1      - 1 (default): add head movement onto the view so other
		                         addons can stack on it, 0: replace the view

	Server console command:
		sv_trackir_allow 0/1   - allow or forbid TrackIR for players on this server

	Menu: Q -> Utilities -> TrackIR

	How the master switch and auto-enable work together:
		enabled = 0                      -> plugin is off, period
		enabled = 1, autoenable = 0      -> plugin is on
		enabled = 1, autoenable = 1      -> plugin is on only while a device is found

	Auto-enable turns the plugin off by itself if the device sends nothing but
	zeros for a few seconds (opentrack closed, tracker stopped), and while it's
	off it looks for the device again every few seconds.

	Auto-enable re-checks the device when:
		- the game starts / a map or server is joined
		- ESC menu (pause) gets closed
		- the game window loses or regains focus
		- you hit "recheck" (console command or menu button)

	Language: the menu and console messages follow the game language
	(gmod_language). Russian if it's "ru", English for everything else.
]]

if CLIENT then
	local math = math
	local net = net
	local Angle = Angle

	-- how long we listen for head data before deciding "no device here"
	-- (right after the module loads the first frames can be all zeros, so give it some time)
	local PROBE_TIME = 5

	-- in auto mode, while the plugin is off, look for the device again this often (seconds)
	local AUTO_RETRY = 10

	----------------------------------------------------------------
	-- Localization (English / Russian, picked from the game language)
	----------------------------------------------------------------
	local L = {
		en = {
			-- convar descriptions
			cv_enabled      = "Master switch: 0 = plugin fully off",
			cv_auto         = "Enable automatically when a TrackIR device is found",
			cv_real         = "Show the real crosshair",
			cv_real_style   = "0 = square, 1 = rounded, 2 = circle outline",
			cv_real_size    = "Real crosshair size",
			cv_real_outline = "Dark outline around the real crosshair",
			cv_game         = "Show the stock game crosshair",
			cv_sens_pitch   = "Pitch sensitivity (look up/down)",
			cv_sens_yaw     = "Yaw sensitivity (look left/right)",
			cv_sens_roll    = "Roll sensitivity (head tilt)",
			cv_sens_pos     = "Head movement sensitivity",
			cv_inv_pitch    = "Invert pitch",
			cv_inv_yaw      = "Invert yaw",
			cv_limit_pitch  = "Max pitch angle",
			cv_limit_yaw    = "Max yaw angle",
			cv_limit_roll   = "Max roll angle",
			cv_position     = "Use head movement (X axis)",
			cv_send_head    = "Sync head to the server (others can see it)",
			cv_send_body    = "Sync body lean to the server (others can see it)",
			cv_netrate      = "How often we send data to the server (per second)",
			cv_debug        = "Print what the device detection sees to the console",
			cv_camera_mode  = "Looking through a camera: 0 = ignore TrackIR, 1 = apply TrackIR on top of the camera",
			cv_chain        = "1 = add head movement onto the view so other addons (cameras, view bob) can stack on it, 0 = replace the view",

			-- console messages
			msg_probe_ok    = "device found (axes sum: %s)",
			msg_probe_fail  = "no device data within %s s (axes sum: %s, frame counter: %s -> %s)",
			msg_lost        = "no head data for %s s, turning off",
			msg_enabled     = "enabled",
			msg_disabled    = "disabled",
			msg_loadfail    = "couldn't load the module: ",
			msg_state       = "plugin active: %s | enabled: %s | autoenable: %s",
			msg_nomodule    = "module is not loaded (is the game window focused?)",

			-- menu
			m_enable        = "Enable TrackIR",
			m_auto          = "Auto-enable (when a TrackIR is found)",
			m_auto_help     = "The device is re-checked on game start / map join, when the ESC menu closes and when the window focus changes.",
			m_recheck       = "Check for the device now",
			m_center        = "Center (current position = center)",
			m_status        = "Print status to console",

			m_h_camera      = "Cameras",
			m_cam_mode      = "When looking through a camera",
			m_cam_ignore    = "Ignore TrackIR (camera stays put)",
			m_cam_apply     = "Apply TrackIR on top of the camera",
			m_chain         = "Stack with other view addons (recommended)",
			m_chain_help    = "On: TrackIR is added onto the view without replacing it, so camera addons and view-bob/tilt addons keep working on top of it. Off: TrackIR replaces the view (old behaviour).",

			m_h_crosshairs  = "Crosshairs",
			m_real          = "Show real crosshair",
			m_game          = "Show game (stock) crosshair",
			m_style         = "Real crosshair style",
			m_style_square  = "Square",
			m_style_round   = "Rounded",
			m_style_circle  = "Circle",
			m_size          = "Real crosshair size",
			m_outline       = "Real crosshair outline",
			m_color         = "Real crosshair color",

			m_h_sens        = "Sensitivity",
			m_pitch         = "Pitch",
			m_yaw           = "Yaw",
			m_roll          = "Roll",
			m_pos           = "Head movement",
			m_inv_pitch     = "Invert pitch",
			m_inv_yaw       = "Invert yaw",

			m_h_limits      = "Angle limits",
			m_lim_pitch     = "Max pitch",
			m_lim_yaw       = "Max yaw",
			m_lim_roll      = "Max roll",

			m_h_misc        = "Advanced",
			m_position      = "Use head movement (X axis)",
			m_head          = "Sync head (visible to others)",
			m_body          = "Sync body (visible to others)",
			m_netrate       = "Server send rate",
			m_reset         = "Reset settings to defaults",
		},

		ru = {
			cv_enabled      = "Главный выключатель: 0 = плагин полностью выключен",
			cv_auto         = "Включаться автоматически, когда найден TrackIR",
			cv_real         = "Показывать реальный прицел",
			cv_real_style   = "0 = квадрат, 1 = скруглённый, 2 = круг",
			cv_real_size    = "Размер реального прицела",
			cv_real_outline = "Тёмная обводка реального прицела",
			cv_game         = "Показывать стандартный игровой прицел",
			cv_sens_pitch   = "Чувствительность наклона (вверх/вниз)",
			cv_sens_yaw     = "Чувствительность поворота (влево/вправо)",
			cv_sens_roll    = "Чувствительность крена (наклон головы)",
			cv_sens_pos     = "Чувствительность смещения головы",
			cv_inv_pitch    = "Инвертировать наклон",
			cv_inv_yaw      = "Инвертировать поворот",
			cv_limit_pitch  = "Максимальный угол наклона",
			cv_limit_yaw    = "Максимальный угол поворота",
			cv_limit_roll   = "Максимальный угол крена",
			cv_position     = "Учитывать смещение головы (ось X)",
			cv_send_head    = "Синхронизировать голову с сервером (видно другим)",
			cv_send_body    = "Синхронизировать корпус с сервером (видно другим)",
			cv_netrate      = "Как часто отправлять данные на сервер (раз в секунду)",
			cv_debug        = "Выводить в консоль, что видит определение устройства",
			cv_camera_mode  = "Просмотр через камеру: 0 = игнорировать TrackIR, 1 = применять TrackIR поверх камеры",
			cv_chain        = "1 = добавлять движение головы к виду, чтобы другие аддоны (камеры, покачивание) работали поверх, 0 = подменять вид",
			msg_probe_ok    = "устройство найдено (сумма осей: %s)",
			msg_probe_fail  = "нет данных от устройства за %s с (сумма осей: %s, счётчик кадров: %s -> %s)",
			msg_lost        = "нет данных головы уже %s с, выключаюсь",

			msg_enabled     = "включён",
			msg_disabled    = "выключен",
			msg_loadfail    = "не удалось загрузить модуль: ",
			msg_state       = "плагин активен: %s | enabled: %s | autoenable: %s",
			msg_nomodule    = "модуль не загружен (окно игры в фокусе?)",

			m_enable        = "Включить TrackIR",
			m_auto          = "Автовключение (если найден TrackIR)",
			m_auto_help     = "Устройство проверяется при запуске игры / входе на карту, закрытии ESC-меню и смене фокуса окна.",
			m_recheck       = "Проверить устройство сейчас",
			m_center        = "Центровать (текущая позиция = центр)",
			m_status        = "Вывести статус в консоль",

			m_h_camera      = "Камеры",
			m_cam_mode      = "При просмотре через камеру",
			m_cam_ignore    = "Игнорировать TrackIR (камера неподвижна)",
			m_cam_apply     = "Применять TrackIR поверх камеры",
			m_chain         = "Совместно с другими аддонами вида (рекомендуется)",
			m_chain_help    = "Вкл: TrackIR добавляется к виду, не подменяя его, поэтому камеры и аддоны покачивания/наклона продолжают работать поверх. Выкл: TrackIR подменяет вид (старое поведение).",

			m_h_crosshairs  = "Прицелы",
			m_real          = "Показывать реальный прицел",
			m_game          = "Показывать игровой (стандартный) прицел",
			m_style         = "Стиль реального прицела",
			m_style_square  = "Квадрат",
			m_style_round   = "Скруглённый",
			m_style_circle  = "Круг",
			m_size          = "Размер реального прицела",
			m_outline       = "Обводка реального прицела",
			m_color         = "Цвет реального прицела",

			m_h_sens        = "Чувствительность",
			m_pitch         = "Наклон (pitch)",
			m_yaw           = "Поворот (yaw)",
			m_roll          = "Крен (roll)",
			m_pos           = "Смещение головы",
			m_inv_pitch     = "Инвертировать наклон",
			m_inv_yaw       = "Инвертировать поворот",

			m_h_limits      = "Ограничения углов",
			m_lim_pitch     = "Макс. наклон",
			m_lim_yaw       = "Макс. поворот",
			m_lim_roll      = "Макс. крен",

			m_h_misc        = "Дополнительно",
			m_position      = "Учитывать смещение головы (ось X)",
			m_head          = "Синхронизировать голову (видно другим)",
			m_body          = "Синхронизировать корпус (видно другим)",
			m_netrate       = "Частота отправки на сервер",
			m_reset         = "Сбросить настройки по умолчанию",
		},
	}

	-- Russian only when the game itself is set to Russian, English otherwise
	local function T(key)
		local langCvar = GetConVar("gmod_language")
		local lang = langCvar and langCvar:GetString() or "en"
		local set = (lang == "ru") and L.ru or L.en

		return set[key] or L.en[key] or key
	end

	----------------------------------------------------------------
	-- ConVars (all of them are saved between sessions)
	----------------------------------------------------------------
	local function CV(name, def, helpKey)
		return CreateClientConVar("trackir_" .. name, def, true, false, helpKey and T(helpKey) or "")
	end

	local cv = {
		enabled       = CV("enabled", "1", "cv_enabled"),
		auto          = CV("autoenable", "1", "cv_auto"),

		-- real crosshair (where the player is actually aiming)
		real          = CV("crosshair_real", "1", "cv_real"),
		real_style    = CV("crosshair_real_style", "1", "cv_real_style"),
		real_size     = CV("crosshair_real_size", "10", "cv_real_size"),
		real_outline  = CV("crosshair_real_outline", "1", "cv_real_outline"),
		real_r        = CV("crosshair_real_r", "64"),
		real_g        = CV("crosshair_real_g", "134"),
		real_b        = CV("crosshair_real_b", "195"),
		real_a        = CV("crosshair_real_a", "170"),

		-- the stock game crosshair
		game          = CV("crosshair_game", "1", "cv_game"),

		-- sensitivity
		sens_pitch    = CV("sens_pitch", "1", "cv_sens_pitch"),
		sens_yaw      = CV("sens_yaw", "1", "cv_sens_yaw"),
		sens_roll     = CV("sens_roll", "1", "cv_sens_roll"),
		sens_pos      = CV("sens_pos", "1", "cv_sens_pos"),
		inv_pitch     = CV("invert_pitch", "0", "cv_inv_pitch"),
		inv_yaw       = CV("invert_yaw", "0", "cv_inv_yaw"),

		-- angle limits
		limit_pitch   = CV("limit_pitch", "70", "cv_limit_pitch"),
		limit_yaw     = CV("limit_yaw", "130", "cv_limit_yaw"),
		limit_roll    = CV("limit_roll", "70", "cv_limit_roll"),

		-- misc
		position      = CV("position", "1", "cv_position"),
		send_head     = CV("send_head", "1", "cv_send_head"),
		send_body     = CV("send_body", "1", "cv_send_body"),
		netrate       = CV("netrate", "66", "cv_netrate"),
		debug         = CV("debug", "0", "cv_debug"),

		-- cameras
		camera_mode   = CV("camera_mode", "0", "cv_camera_mode"),
		chain         = CV("chain", "1", "cv_chain"),
	}

	----------------------------------------------------------------
	-- State
	----------------------------------------------------------------
	local active = false   -- plugin is really running right now
	local loaded = false   -- the TrackIR module has been required already
	local loadFailed = false -- require() blew up, don't keep retrying on a timer
	local probing = false  -- a device probe is running right now
	local wacHooked = false
	local data1, data2     -- what we want to send to the server
	local _data1, _data2   -- what we sent last time

	-- values after centering, sensitivity and inversion
	local P   = { Pitch = 0, Yaw = 0, Roll = 0, X = 0 }
	local off = { Pitch = 0, Yaw = 0, Roll = 0, X = 0 }

	local function Say(msg)
		MsgC(Color(100, 200, 255), "[TrackIR] ", Color(255, 255, 255), msg, "\n")
	end

	----------------------------------------------------------------
	-- Helpers
	----------------------------------------------------------------
	local function RotateVector(vector, angle)
		local _vector = vector
		_vector:Rotate(angle)

		return _vector
	end

	-- no ugly view like 'max is 130, min is 130, more like max is 130 but every ° over 130 is reducted (1/exp function)
	local function Nicerlimit(var, minu, maxi)
		local _maxi = maxi + 0.2 * maxi -- +20%
		local _minu = minu + 0.2 * minu
		local _var = var

		if var >= maxi then
			_var = var - maxi
		else
			if var <= minu then
				_var = var - minu
			else
				_var = 0
			end
		end

		-- _var is now "how much its over the limit"
		if _var >= 0 then
			var = var + math.sqrt(_var) / 2 - _var
		else
			var = var + -1 * math.sqrt(math.abs(_var)) / 2 - _var
		end

		var = math.min(math.max(_minu, var), _maxi)

		return var
	end

	local function Limits()
		local lp = math.max(cv.limit_pitch:GetFloat(), 1)
		local ly = math.max(cv.limit_yaw:GetFloat(), 1)
		local lr = math.max(cv.limit_roll:GetFloat(), 1)

		return lp, ly, lr
	end

	-- vehicles and aircraft have their own camera, so we stay out of the way
	local function ShouldSkipView()
		local ply = LocalPlayer()
		if not IsValid(ply) then return true end

		local vehicle = ply:GetVehicle()

		if ply:InVehicle() then
			return true
		end

		if IsValid(vehicle) and IsValid(vehicle:GetNWEntity("wac_aircraft")) then
			return true
		end

		if ply:GetNWEntity("ScriptedVehicle", NULL) ~= NULL and string.StartWith(ply:GetNetworkedEntity("ScriptedVehicle", NULL):GetClass(), "sent_") then
			return true
		end

		return false
	end

	-- true while the player looks through something that isn't their own eyes
	-- (the Camera tool and most camera entities use SetViewEntity for this)
	local function ViewingThroughCamera()
		local ply = LocalPlayer()
		if not IsValid(ply) then return false end

		local viewEnt = ply:GetViewEntity()

		return IsValid(viewEnt) and viewEnt ~= ply
	end

	-- should we leave the view alone because of a camera?
	local function CameraSkip()
		return cv.camera_mode:GetInt() == 0 and ViewingThroughCamera()
	end

	-- shared view math. add = true for wac, where we add on top of the current angles
	local function BuildView(origin, angles, fov, znear, zfar, add)
		local lp, ly, lr = Limits()

		local ang1 = Angle(Nicerlimit(P.Pitch / 90, -lp, lp) + (add and angles[1] or 0), 0, 0)
		local ang2 = Angle(0, Nicerlimit(P.Yaw / 90, -ly, ly) + (add and angles[2] or 0), 0)
		local ang3 = Angle(0, 0, Nicerlimit(-1 * P.Roll / 90 + -2 * P.X / 900, -lr, lr))
		ang3:RotateAroundAxis(ang3:Right(), -1 * ang1[1])
		ang3:RotateAroundAxis(ang3:Up(), ang2[2])
		Var_TrackIR_Angle_W = ang3

		local view = {}
		view.origin = origin + RotateVector(Vector(0, Nicerlimit(P.X / 500, -15, 10), -1 * math.abs(Nicerlimit(P.X / 900, -5, 5))), angles)
		view.angles = angles + (Var_TrackIR_Angle_W or Angle(0, 0, 0))
		view.fov = fov
		view.znear = znear
		view.zfar = zfar
		view.drawviewer = false

		return view
	end

	----------------------------------------------------------------
	-- Hooks
	----------------------------------------------------------------
	local function TrackIR_View(ply, origin, angles, fov, znear, zfar)
		if not active then return end
		if ShouldSkipView() or CameraSkip() then return end

		local view = BuildView(origin, angles, fov, znear, zfar, false)

		if cv.chain:GetBool() then
			-- CalcView hooks can't be stacked if we return a table: the first hook that
			-- returns one wins and the rest (other addons, SWEP:CalcView...) never run.
			-- Instead we change origin/angles in place and return nothing, so everything
			-- that runs after us works on top of the head-tracked view.
			origin.x, origin.y, origin.z = view.origin.x, view.origin.y, view.origin.z
			angles.p, angles.y, angles.r = view.angles.p, view.angles.y, view.angles.r

			return
		end

		return view
	end

	local function TrackIR_View2(ply, origin, angles, fov, znear, zfar)
		if not active then return end

		return BuildView(origin, angles, fov, znear, zfar, true)
	end

	local function TrackIR_Timer()
		-- the best way would be to make it 60/120 times per sec. (i mean, not 60-120, it's 60 OR 120 (depending of the trackir device))
		TrackIR.Update()
		TrackIR.Pitch = TrackIR.get_Pitch() or 0
		TrackIR.Yaw = TrackIR.get_Yaw() or 0
		TrackIR.Roll = TrackIR.get_Roll() or 0
		TrackIR.X = TrackIR.get_X() or 0
		TrackIR.Y = TrackIR.get_Y() or 0
		TrackIR.Z = TrackIR.get_Z() or 0
		TrackIR.LostFrames = TrackIR_LostFrames and TrackIR.get_LostFrames() or 0

		-- apply centering, sensitivity and inversion
		local sp = cv.sens_pitch:GetFloat() * (cv.inv_pitch:GetBool() and -1 or 1)
		local sy = cv.sens_yaw:GetFloat() * (cv.inv_yaw:GetBool() and -1 or 1)
		local sr = cv.sens_roll:GetFloat()

		P.Pitch = (TrackIR.Pitch - off.Pitch) * sp
		P.Yaw = (TrackIR.Yaw - off.Yaw) * sy
		P.Roll = (TrackIR.Roll - off.Roll) * sr

		if cv.position:GetBool() then
			P.X = (TrackIR.X - off.X) * cv.sens_pos:GetFloat()
		else
			P.X = 0
		end

		local lp, ly, lr = Limits()

		Var_TrackIR_Angle_APIRAW = Angle(Nicerlimit(P.Pitch / 90, -lp, lp), Nicerlimit(P.Yaw / 90, -ly, ly), Nicerlimit(-1 * P.Roll / 90 + -2 * P.X / 900, -lr, lr))
		data1 = Angle(Nicerlimit(P.Roll / 90 + P.X / 900, -lr, lr), -1 * Nicerlimit(P.Pitch / 90, -lp, lp), Nicerlimit(P.Yaw / 90, -ly, ly))
		data2 = -1 * P.X / 500
	end

	local function TrackIR_HUDPaint()
		if not cv.real:GetBool() then return end

		-- don't get lost my friend, know where you're aiming ;)
		local ply = LocalPlayer()
		if not IsValid(ply) then return end

		local tr = (util.TraceLine(util.GetPlayerTrace(ply)).HitPos):ToScreen()
		if not tr.visible then return end

		local s = math.max(cv.real_size:GetInt(), 2)
		local h = s / 2
		local style = cv.real_style:GetInt()
		local col = Color(cv.real_r:GetInt(), cv.real_g:GetInt(), cv.real_b:GetInt(), cv.real_a:GetInt())

		if style == 2 then
			-- circle outline
			surface.DrawCircle(tr.x, tr.y, h, col.r, col.g, col.b, col.a)
			if cv.real_outline:GetBool() then
				surface.DrawCircle(tr.x, tr.y, h + 1, 0, 0, 0, math.min(col.a, 105))
			end
		else
			local radius = (style == 1) and 4 or 0

			if cv.real_outline:GetBool() then
				draw.RoundedBox(0, tr.x - h - 1, tr.y - h - 1, s + 2, s + 2, Color(0, 0, 0, 105))
			end

			draw.RoundedBox(radius, tr.x - h, tr.y - h, s, s, col)
		end
	end

	-- hide the stock crosshair if the player asked for that
	hook.Add("HUDShouldDraw", "TrackIR_HideGameCrosshair", function(name)
		if active and name == "CHudCrosshair" and not cv.game:GetBool() then
			return false
		end
	end)

	----------------------------------------------------------------
	-- Networking
	----------------------------------------------------------------
	-- tell the server to put head and spine back to normal
	local function SendReset()
		net.Start("TrackIR_Data.h")
		net.WriteAngle(Angle(0, 0, 0))
		net.SendToServer()

		net.Start("TrackIR_Data.s")
		net.WriteFloat(0)
		net.SendToServer()
	end

	local function StartNetTimer()
		timer.Create("TrackIR_Net", 1 / math.Clamp(cv.netrate:GetFloat(), 1, 100), 0, function()
			if not active or not data1 or not data2 then return end

			local d1 = cv.send_head:GetBool() and data1 or Angle(0, 0, 0)
			local d2 = cv.send_body:GetBool() and data2 or 0

			-- only send when something actually changed
			if d1 ~= _data1 then
				_data1 = d1
				net.Start("TrackIR_Data.h")
				net.WriteAngle(d1)
				net.SendToServer()
			end

			if d2 ~= _data2 then
				_data2 = d2
				net.Start("TrackIR_Data.s")
				net.WriteFloat(d2)
				net.SendToServer()
			end
		end)
	end

	----------------------------------------------------------------
	-- Loading the module, turning the plugin on and off
	----------------------------------------------------------------
	-- returns true when the module is ready, otherwise false + the reason ("focus" or "error")
	local function LoadModule()
		if loaded then return true end

		-- the module needs the game window to have focus, otherwise
		-- *AfxGetMainWnd() inside of it returns NULL (0x0) and things go bad
		if not system.HasFocus() then
			return false, "focus"
		end

		local ok, err = pcall(require, "TrackIR") -- no shit sherlock

		if not ok then
			Say(T("msg_loadfail") .. tostring(err))
			loadFailed = true

			return false, "error"
		end

		loaded = true
		loadFailed = false

		return true
	end

	----------------------------------------------------------------
	-- View hook
	----------------------------------------------------------------
	local function RemoveViewHook()
		hook.Remove("CalcView", "trackirview")
	end

	local function ApplyViewHook()
		RemoveViewHook()

		if active then
			hook.Add("CalcView", "trackirview", TrackIR_View)
		end
	end

	local function Disable()
		if not active then return end
		active = false

		hook.Remove("Think", "TrackIRupdate")
		hook.Remove("Think", "TrackIR_Watchdog")
		RemoveViewHook()
		hook.Remove("HUDPaint", "TrackIr real aiming")
		timer.Remove("TrackIR_Net")

		SendReset()

		data1, data2, _data1, _data2 = nil, nil, nil, nil
		Var_TrackIR_Angle_W = nil
		Var_TrackIR_Angle_APIRAW = nil

		Say(T("msg_disabled"))
	end

	local function Enable()
		if active then return end

		local ok, reason = LoadModule()

		if not ok then
			-- manual mode and the module is broken: switch ourselves off so we don't retry forever
			if reason == "error" and not cv.auto:GetBool() then
				RunConsoleCommand("trackir_enabled", "0")
			end

			return
		end

		TrackIR.Pitch = 0
		TrackIR.Roll = 0
		TrackIR.Yaw = 0
		TrackIR.X = 0
		TrackIR.Y = 0
		TrackIR.Z = 0

		active = true
		_data1, _data2 = nil, nil

		hook.Add("Think", "TrackIRupdate", TrackIR_Timer)

		-- auto mode only: if the device goes quiet (opentrack closed, tracker stopped)
		-- there will be nothing but exact zeros, so switch ourselves off
		local lastAlive = CurTime()

		hook.Add("Think", "TrackIR_Watchdog", function()
			if not cv.auto:GetBool() then
				lastAlive = CurTime()

				return
			end

			local sum = math.abs(TrackIR.Pitch or 0) + math.abs(TrackIR.Yaw or 0) + math.abs(TrackIR.Roll or 0)
				+ math.abs(TrackIR.X or 0) + math.abs(TrackIR.Y or 0) + math.abs(TrackIR.Z or 0)

			if sum ~= 0 then
				lastAlive = CurTime()
			elseif CurTime() - lastAlive > PROBE_TIME then
				Say(string.format(T("msg_lost"), tostring(PROBE_TIME)))
				Disable()
			end
		end)
		hook.Add("HUDPaint", "TrackIr real aiming", TrackIR_HUDPaint)
		ApplyViewHook()
		StartNetTimer()

		-- the wac hook can't be removed cleanly, so we hook it once
		-- and let TrackIR_View2 bail out when the plugin is off
		if wac and not wacHooked then
			wac.hook("CalcView", "trackirview", TrackIR_View2)
			wacHooked = true
		end

		Say(T("msg_enabled"))
	end

	----------------------------------------------------------------
	-- Device detection (auto-enable)
	----------------------------------------------------------------
	-- A device counts as alive when any of the six axes is non-zero: a real
	-- tracker never reports exact zeros for long, a missing device or closed
	-- TrackIR software does.
	-- The frame counter from get_Debug is only printed for troubleshooting, it
	-- can keep ticking even when no tracker is running. get_Status is not used
	-- either: on opentrack it stays 0 whether or not data is flowing.
	-- The module only refreshes its numbers when Update() is called,
	-- so we have to call it ourselves while probing.
	local function StopProbe()
		probing = false
		hook.Remove("Think", "TrackIR_Probe")
	end

	local function ReadFrame()
		if not TrackIR.get_Debug then return nil end

		local ok, str = pcall(TrackIR.get_Debug)
		if not ok or type(str) ~= "string" then return nil end

		return tonumber(string.match(str, "Frame%s*=%s*(%d+)"))
	end

	local function StartProbe()
		local stopAt = CurTime() + PROBE_TIME
		local firstFrame, lastFrame, maxSum = ReadFrame(), nil, 0

		probing = true

		hook.Add("Think", "TrackIR_Probe", function()
			pcall(TrackIR.Update)

			local sum = math.abs(TrackIR.get_Pitch() or 0)
				+ math.abs(TrackIR.get_Yaw() or 0)
				+ math.abs(TrackIR.get_Roll() or 0)
				+ math.abs(TrackIR.get_X() or 0)
				+ math.abs(TrackIR.get_Y() or 0)
				+ math.abs(TrackIR.get_Z() or 0)

			maxSum = math.max(maxSum, sum)

			if sum ~= 0 then
				StopProbe()

				if cv.debug:GetBool() then
					Say(string.format(T("msg_probe_ok"), tostring(sum)))
				end

				Enable() -- does nothing if we're already running
			elseif CurTime() > stopAt then
				StopProbe()

				if cv.debug:GetBool() then
					lastFrame = ReadFrame()
					Say(string.format(T("msg_probe_fail"), tostring(PROBE_TIME), tostring(maxSum), tostring(firstFrame), tostring(lastFrame)))
				end

				Disable()
			end
		end)
	end

	-- the one function that decides what the plugin should be doing right now
	local function Refresh()
		StopProbe()

		if not cv.enabled:GetBool() then
			Disable()

			return
		end

		if not cv.auto:GetBool() then
			Enable()

			return
		end

		-- auto mode: we need the module loaded before we can ask it anything
		local ok, reason = LoadModule()

		if not ok then
			-- no focus yet: leave things as they are, the focus watcher will call us again
			if reason == "focus" then return end

			-- module is missing or broken, so there's no device for us to use
			Disable()

			return
		end

		StartProbe()
	end

	-- auto mode and the plugin is off: peek for the device every now and then,
	-- so starting opentrack later still works without touching ESC or the window
	timer.Create("TrackIR_AutoRetry", AUTO_RETRY, 0, function()
		if active or probing or loadFailed then return end
		if not cv.enabled:GetBool() or not cv.auto:GetBool() then return end
		if not system.HasFocus() or gui.IsGameUIVisible() then return end

		Refresh()
	end)

	cvars.AddChangeCallback("trackir_enabled", function()
		Refresh()
	end, "TrackIR_Enabled")

	cvars.AddChangeCallback("trackir_autoenable", function()
		Refresh()
	end, "TrackIR_AutoEnable")

	cvars.AddChangeCallback("trackir_netrate", function()
		if active then StartNetTimer() end
	end, "TrackIR_NetRate")

	-- game language changed: rebuild the spawnmenu so our menu picks up the new language
	cvars.AddChangeCallback("gmod_language", function()
		timer.Simple(0, function()
			RunConsoleCommand("spawnmenu_reload")
		end)
	end, "TrackIR_Language")

	----------------------------------------------------------------
	-- Re-check triggers: focus changes and the ESC menu
	----------------------------------------------------------------
	local lastFocus = system.HasFocus()
	local lastUI = gui.IsGameUIVisible()

	hook.Add("Think", "TrackIR_Watcher", function()
		local focus = system.HasFocus()
		local ui = gui.IsGameUIVisible()

		-- window lost or regained focus, or the ESC menu just closed
		if focus ~= lastFocus or (lastUI and not ui) then
			Refresh()
		end

		lastFocus, lastUI = focus, ui
	end)

	-- map loaded / joined a server
	hook.Add("InitPostEntity", "TrackIR_MapLoaded", function()
		Refresh()
	end)

	-- first start (also covers reloading this file mid-game, where InitPostEntity won't fire)
	hook.Add("Tick", "TrackIR_Startup", function()
		hook.Remove("Tick", "TrackIR_Startup")
		Refresh()
	end)

	----------------------------------------------------------------
	-- Console commands
	----------------------------------------------------------------
	concommand.Add("trackir_toggle", function()
		RunConsoleCommand("trackir_enabled", cv.enabled:GetBool() and "0" or "1")
	end)

	concommand.Add("trackir_recheck", function()
		Refresh()
	end)

	concommand.Add("trackir_center", function()
		if not active or not TrackIR then return end

		off.Pitch = TrackIR.Pitch or 0
		off.Yaw = TrackIR.Yaw or 0
		off.Roll = TrackIR.Roll or 0
		off.X = TrackIR.X or 0
	end)

	concommand.Add("trackir_reset", function()
		for k, v in pairs(cv) do
			-- leave the master switch alone, resetting settings shouldn't kill the plugin
			if k ~= "enabled" then
				RunConsoleCommand(v:GetName(), v:GetDefault())
			end
		end

		off.Pitch, off.Yaw, off.Roll, off.X = 0, 0, 0, 0
	end)

	-- dumps whatever the module knows about itself, handy for checking the device
	concommand.Add("trackir_status", function()
		Say(string.format(T("msg_state"), tostring(active), tostring(cv.enabled:GetBool()), tostring(cv.auto:GetBool())))

		if not LoadModule() then
			Say(T("msg_nomodule"))

			return
		end

		-- the module only updates its numbers on Update(), without this we'd print stale data
		pcall(TrackIR.Update)

		for _, name in ipairs({"get_Ver", "get_Status", "get_Debug"}) do
			local fn = TrackIR[name]

			if fn then
				local ok, res = pcall(fn)
				Say(name .. ": " .. tostring(ok and res or ("error: " .. tostring(res))))
			end
		end
	end)

	----------------------------------------------------------------
	-- Menu: Utilities -> TrackIR
	----------------------------------------------------------------
	hook.Add("PopulateToolMenu", "TrackIR_Menu", function()
		spawnmenu.AddToolMenuOption("Utilities", "TrackIR", "trackir_settings", "TrackIR", "", "", function(panel)
			panel:ClearControls()

			panel:CheckBox(T("m_enable"), "trackir_enabled")
			panel:CheckBox(T("m_auto"), "trackir_autoenable")
			panel:Help(T("m_auto_help"))
			panel:Button(T("m_recheck"), "trackir_recheck")
			panel:Button(T("m_center"), "trackir_center")
			panel:Button(T("m_status"), "trackir_status")

			panel:Help(T("m_h_crosshairs"))
			panel:CheckBox(T("m_real"), "trackir_crosshair_real")
			panel:CheckBox(T("m_game"), "trackir_crosshair_game")

			local combo = panel:ComboBox(T("m_style"), "trackir_crosshair_real_style")
			combo:AddChoice(T("m_style_square"), 0)
			combo:AddChoice(T("m_style_round"), 1)
			combo:AddChoice(T("m_style_circle"), 2)

			panel:NumSlider(T("m_size"), "trackir_crosshair_real_size", 2, 40, 0)
			panel:CheckBox(T("m_outline"), "trackir_crosshair_real_outline")

			panel:AddControl("Color", {
				Label = T("m_color"),
				Red = "trackir_crosshair_real_r",
				Green = "trackir_crosshair_real_g",
				Blue = "trackir_crosshair_real_b",
				Alpha = "trackir_crosshair_real_a",
			})

			panel:Help(T("m_h_sens"))
			panel:NumSlider(T("m_pitch"), "trackir_sens_pitch", 0, 3, 2)
			panel:NumSlider(T("m_yaw"), "trackir_sens_yaw", 0, 3, 2)
			panel:NumSlider(T("m_roll"), "trackir_sens_roll", 0, 3, 2)
			panel:NumSlider(T("m_pos"), "trackir_sens_pos", 0, 3, 2)
			panel:CheckBox(T("m_inv_pitch"), "trackir_invert_pitch")
			panel:CheckBox(T("m_inv_yaw"), "trackir_invert_yaw")

			panel:Help(T("m_h_camera"))
			local camCombo = panel:ComboBox(T("m_cam_mode"), "trackir_camera_mode")
			camCombo:AddChoice(T("m_cam_ignore"), 0)
			camCombo:AddChoice(T("m_cam_apply"), 1)
			panel:CheckBox(T("m_chain"), "trackir_chain")
			panel:Help(T("m_chain_help"))

			panel:Help(T("m_h_limits"))
			panel:NumSlider(T("m_lim_pitch"), "trackir_limit_pitch", 10, 90, 0)
			panel:NumSlider(T("m_lim_yaw"), "trackir_limit_yaw", 10, 180, 0)
			panel:NumSlider(T("m_lim_roll"), "trackir_limit_roll", 10, 90, 0)

			panel:Help(T("m_h_misc"))
			panel:CheckBox(T("m_position"), "trackir_position")
			panel:CheckBox(T("m_head"), "trackir_send_head")
			panel:CheckBox(T("m_body"), "trackir_send_body")
			panel:NumSlider(T("m_netrate"), "trackir_netrate", 10, 100, 0)

			panel:Button(T("m_reset"), "trackir_reset")
		end)
	end)
end

if SERVER then
	util.AddNetworkString("TrackIR_Data.h")
	util.AddNetworkString("TrackIR_Data.s")

	local sv_allow = CreateConVar("sv_trackir_allow", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Allow players to use TrackIR on this server")

	function TrackIR_Applybone(ent, angle, bone)
		if type(angle) == "number" then
			angle = Angle(angle, 0, 0)
		end

		local headBoneID = ent:LookupBone(bone)

		if headBoneID then
			ent:ManipulateBoneAngles(headBoneID, angle)
		end
	end

	net.Receive("TrackIR_Data.h", function(lenght, ply)
		if not IsValid(ply) then return end

		local ang = net.ReadAngle()

		-- server forbids TrackIR: force the bone back to neutral
		if not sv_allow:GetBool() then
			ang = Angle(0, 0, 0)
		end

		-- never trust the client, keep the angles sane
		ang.p = math.Clamp(ang.p, -180, 180)
		ang.y = math.Clamp(ang.y, -180, 180)
		ang.r = math.Clamp(ang.r, -180, 180)

		TrackIR_Applybone(ply, ang, "ValveBiped.Bip01_Head1")
	end)

	net.Receive("TrackIR_Data.s", function(lenght, ply)
		if not IsValid(ply) then return end

		local val = net.ReadFloat()

		if not sv_allow:GetBool() then
			val = 0
		end

		TrackIR_Applybone(ply, math.Clamp(val, -90, 90), "ValveBiped.Bip01_Spine1")
	end)
end
