local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
  typedef uint64_t UniverseID;
  typedef int32_t TradeRuleID;

  const char* GetObjectIDCode(UniverseID objectid);

	uint32_t GetNumCargoTransportTypes(UniverseID containerid, bool merge);
  uint32_t GetCargoTransportTypes(StorageInfo* result, uint32_t resultlen, UniverseID containerid, bool merge, bool aftertradeorders);

  bool GetContainerWareIsBuyable(UniverseID containerid, const char* wareid);
  bool GetContainerWareIsSellable(UniverseID containerid, const char* wareid);

  int32_t GetContainerBuyLimit(UniverseID containerid, const char* wareid);
  int32_t GetContainerSellLimit(UniverseID containerid, const char* wareid);

  bool HasContainerBuyLimitOverride(UniverseID containerid, const char* wareid);
  bool HasContainerSellLimitOverride(UniverseID containerid, const char* wareid);
  bool HasContainerOwnTradeRule(UniverseID containerid, const char* ruletype, const char* wareid);

  void ClearContainerBuyLimitOverride(UniverseID containerid, const char* wareid);
  void ClearContainerSellLimitOverride(UniverseID containerid, const char* wareid);

  void SetContainerBuyLimitOverride(UniverseID containerid, const char* wareid, int32_t amount);
  void SetContainerSellLimitOverride(UniverseID containerid, const char* wareid, int32_t amount);

  void SetContainerTradeRule(UniverseID containerid, TradeRuleID id, const char* ruletype, const char* wareid, bool value);
  bool IsPlayerTradeRuleDefault(TradeRuleID id, const char* ruletype);

  void SetContainerWareIsBuyable(UniverseID containerid, const char* wareid, bool allowed);
  void SetContainerWareIsSellable(UniverseID containerid, const char* wareid, bool allowed);

  TradeRuleID GetContainerTradeRuleID(UniverseID containerid, const char* ruletype, const char* wareid);

  void AddTradeWare(UniverseID containerid, const char* wareid);
	void RemoveTradeWare(UniverseID containerid, const char* wareid);
]]

local menu = nil
local playerId = nil

local texts = {
  title = ReadText(1972092410, 1001),
  station = ReadText(1972092410, 1011),
  stationOne = ReadText(1972092410, 1011),
  stationTwo = ReadText(1972092410, 1012),
  noMatchingStations = ReadText(1972092410, 1019),
  ware = ReadText(1972092410, 1101),
  storage = ReadText(1972092410, 1102),
  rule = ReadText(1972092410, 1103),
  price = ReadText(1972092410, 1104),
  priceSuffix = ReadText(1001, 101),
  amount = ReadText(1972092410, 1105),
  buyOfferSellOffer = ReadText(1972092410, 1111),
  selectStationOnePrompt = ReadText(1972092410, 1201),
  selectStationTwoPrompt = ReadText(1972092410, 1202),
  noWaresAvailable = ReadText(1972092410, 1203),
  buyOffer = ReadText(1001, 8309),
  sellOffer = ReadText(1001, 8308),
  auto = ReadText(1972092410, 1211),
  noBuyOffer = ReadText(1972092410, 1212),
  noSellOffer = ReadText(1972092410, 1213),
  resource = ReadText(1972092410, 1121),
  intermediate = ReadText(1972092410, 1122),
  product = ReadText(1972092410, 1123),
  trade = ReadText(1972092410, 1124),
  pageInfo = ReadText(1972092410, 1301),
  confirmSave = ReadText(1972092410, 1401),
  saveButton = ReadText(1972092410, 1411),
  cancelButton = ReadText(1972092410, 1419),
  acceptButton = "Accept",
  statusNoStationSelected = ReadText(1972092410, 2001),
  statusNoWaresAvailable = ReadText(1972092410, 2002),
  statusSavedWithWarnings = ReadText(1972092410, 2012),
  statusSuccess = ReadText(1972092410, 2011),
  statusSelectionInfo = ReadText(1972092410, 2101),
}


local overrideIcons = {
}
overrideIcons[true] = "\27[menu_radio_button_off]\27X"
overrideIcons[false] = "\27[menu_radio_button_on]\27X"

local overrideIconsTextProperties = {
}
overrideIconsTextProperties[true] = { halign = "center" }
overrideIconsTextProperties[false] = { halign = "center", color = Color["text_inactive"] }

local wareTypeSortOrder = {
  resource = 1,
  intermediate = 2,
  product = 3,
  trade = 4
}

local tradeRuleNames = nil

local function copyAndEnrichTable(src, extraInfo)
  local dest = {}
  for k, v in pairs(src) do
    dest[k] = v
  end
  for k, v in pairs(extraInfo) do
    dest[k] = v
  end
  return dest
end

local checkboxSize = Helper.scaleX(20)
local tableHeadersTextProperties = copyAndEnrichTable(Helper.headerRowCenteredProperties,
  { fontsize = Helper.standardFontSize, height = Helper.standardTextHeight })
local wareNameTextProperties = copyAndEnrichTable(Helper.subHeaderTextProperties, { halign = "center", color = Color["table_row_highlight"] })
local cargoAmountTextProperties = copyAndEnrichTable(Helper.subHeaderTextProperties, { halign = "right", color = Color["table_row_highlight"] })
local textCategoryProperties = { halign = "left", color = Color["text_notification_text_lowlight"], minRowHeight = checkboxSize }

local tradeRulesRoots = {
  global = ReadText(1001, 8366),
  station = ReadText(1001, 3),
  ware = ReadText(1001, 45),
}

local Lib = require("extensions.sn_mod_support_apis.ui.Library")

local function debugTrace(message)
  local text = "TradesEditor: " .. message
  if type(DebugError) == "function" then
    DebugError(text)
  end
end

local function toUniverseId(value)
  if value == nil then
    return 0
  end

  if type(value) == "number" then
    return value
  end

  local idStr = tostring(value)
  if idStr == "" or idStr == "0" then
    return 0
  end

  return ConvertStringTo64Bit(idStr)
end


local function getStationName(id)
  if id == 0 then
    return "Unknown"
  end
  local name = GetComponentData(ConvertStringToLuaID(tostring(id)), "name")
  local idCode = ffi.string(C.GetObjectIDCode(id))
  return string.format("%s (%s)", name, idCode)
end

local function collectWaresAndProductionSignature(entry)
  if entry.productionSignature then
    return
  end

  local products, rawWares, cargoWares = GetComponentData(entry.id, "products", "tradewares", "cargo")
  if type(products) ~= "table" then
    products = {}
  end
  if type(rawWares) ~= "table" then
    rawWares = {}
  end
  if type(cargoWares) ~= "table" then
    cargoWares = {}
  end
  table.sort(products)
  entry.products = products
  entry.productionSignature = table.concat(products, "|")
  local waresSet = {}
  local wares = {}
  for i = 1, #products do
    waresSet[products[i]] = true
    wares[#wares + 1] = products[i]
  end
  for i = 1, #rawWares do
    if (not waresSet[rawWares[i]]) then
      wares[#wares + 1] = rawWares[i]
      waresSet[rawWares[i]] = true
    end
  end
  for ware, amount in pairs(cargoWares) do
    if (not waresSet[ware]) then
      wares[#wares + 1] = ware
      waresSet[ware] = true
    end
  end
  table.sort(wares)
  entry.tradeData = {}
  entry.tradeData.wares = wares
  entry.tradeData.waresAmounts = cargoWares
  entry.tradeData.waresSet = waresSet
end

local function buildStationCache()
  local stations = {}
  local options = {}
  local list = GetContainedStationsByOwner("player", nil, true) or {}

  for i = 1, #list do
    local id = list[i]
    local id64 = toUniverseId(id)
    if id and id64 and (id64 ~= 0) then
      local entry = {
        id = id,
        id64 = id64,
      }
      debugTrace("Found station: " .. tostring(id) .. " / " .. tostring(id64))
      entry.displayName = getStationName(entry.id64)
      local numStorages = C.GetNumCargoTransportTypes(entry.id64, true)
      local sector, isshipyard, iswharf = GetComponentData(entry.id64, "sector", "isshipyard", "iswharf")
      entry.sector = sector
      if isshipyard or iswharf then
        debugTrace("Skipping station that is a shipyard or wharf: " .. tostring(entry.displayName))
      elseif numStorages == 0 then
        debugTrace("Skipping station without cargo capacity: " .. tostring(entry.displayName))
      else
        collectWaresAndProductionSignature(entry)
        stations[id64] = entry
        options[#options + 1] = { id = id64, icon = "", text = entry.displayName, text2 = sector, displayremoveoption = false }
      end
    end
  end

  table.sort(options, function(a, b)
    return a.text < b.text
  end)

  return stations, options
end

local function ensureTradeRuleNames()
  if tradeRuleNames then
    return
  end
  if type(Helper) ~= "table" then
    return
  end
  if type(Helper.updateTradeRules) == "function" then
    Helper.updateTradeRules()
  end
  local mapping = {}
  if type(Helper.traderuleOptions) == "table" then
    for _, option in ipairs(Helper.traderuleOptions) do
      mapping[option.id] = option.text
    end
  end
  tradeRuleNames = mapping
end

local function getCargoCapacity(container, transport)
  local numStorages = C.GetNumCargoTransportTypes(container, true)
  local buf = ffi.new("StorageInfo[?]", numStorages)
  local count = C.GetCargoTransportTypes(buf, numStorages, container, true, false)
  local capacity = 0
  for i = 0, count - 1 do
    local tags = menu and menu.getTransportTagsFromString(ffi.string(buf[i].transport)) or {}
    if tags[transport] == true then
      capacity = capacity + buf[i].capacity
    end
  end
  return capacity
end

local function collectTradeData(entry, forceRefresh)
  if entry.tradeData and entry.tradeData.waresMap and not forceRefresh then
    return entry.tradeData
  end
  if forceRefresh then
    entry.tradeData = nil
    entry.productionSignature = nil
  end
  if not entry.tradeData then
    collectWaresAndProductionSignature(entry)
  end
  local container = entry.id64
  local wares = entry.tradeData and entry.tradeData.wares or {}
  local map = {}
  local stationBuyRule = C.GetContainerTradeRuleID(container, "buy", "")
  local stationBuyOwnRule = C.HasContainerOwnTradeRule(container, "buy", "")
  local stationSellRule = C.GetContainerTradeRuleID(container, "sell", "")
  local stationSellOwnRule = C.HasContainerOwnTradeRule(container, "sell", "")
  local cargoCapacities = {}

  if #wares > 0 then
    for i = 1, #wares do
      local ware = wares[i]
      local name, transport, minPrice, maxPrice = GetWareData(ware, "name", "transport", "minprice", "maxprice")
      if transport and cargoCapacities[transport] == nil then
        cargoCapacities[transport] = getCargoCapacity(container, transport)
      end
      local wareType = Helper.getContainerWareType(container, ware)
      local storageLimit = GetWareProductionLimit(container, ware)
      local storageLimitPercentage = cargoCapacities[transport] and cargoCapacities[transport] > 0 and 100.00 * storageLimit / cargoCapacities[transport] or
          100.00
      local storageLimitOverride = HasContainerStockLimitOverride(container, ware)
      local buyAllowed = C.GetContainerWareIsBuyable(container, ware)
      local buyLimit = C.GetContainerBuyLimit(container, ware)
      local buyOverride = C.HasContainerBuyLimitOverride(container, ware)
      local buyPrice = RoundTotalTradePrice(GetContainerWarePrice(container, ware, true))
      local buyPriceOverride = HasContainerWarePriceOverride(container, ware, true)
      local buyRuleId = C.GetContainerTradeRuleID(container, "buy", ware)
      local buyOwnRule = C.HasContainerOwnTradeRule(container, "buy", ware)
      local buyRuleRoot = buyOwnRule and "ware" or stationBuyOwnRule and "station" or "global"

      local sellAllowed = C.GetContainerWareIsSellable(container, ware)
      local sellLimit = C.GetContainerSellLimit(container, ware)
      local sellOverride = C.HasContainerSellLimitOverride(container, ware)
      local sellPrice = RoundTotalTradePrice(GetContainerWarePrice(container, ware, false))
      local sellPriceOverride = HasContainerWarePriceOverride(container, ware, false)
      local sellRuleId = C.GetContainerTradeRuleID(container, "sell", ware)
      local sellOwnRule = C.HasContainerOwnTradeRule(container, "sell", ware)
      local sellRuleRoot = sellOwnRule and "ware" or stationSellOwnRule and "station" or "global"

      map[ware] = {
        ware = ware,
        name = name,
        type = wareType,
        transport = transport,
        minPrice = minPrice,
        maxPrice = maxPrice,
        amount = entry.tradeData.waresAmounts[ware] or 0,
        storageLimit = storageLimit,
        storageLimitPercentage = storageLimitPercentage,
        storageLimitOverride = storageLimitOverride,
        buy = {
          allowed = (wareType == "resource") or (wareType == "intermediate") or buyAllowed or buyOverride,
          limit = buyLimit,
          limitPercentage = storageLimit > 0 and 100.00 * buyLimit / storageLimit or 100.00,
          limitOverride = buyOverride,
          price = buyPrice,
          priceOverride = buyPriceOverride,
          rule = buyRuleId,
          ruleOverride = buyOwnRule,
          ruleRoot = buyRuleRoot,
        },
        sell = {
          allowed = (wareType == "product") or (wareType == "intermediate") or sellAllowed or sellOverride,
          limit = sellLimit,
          limitPercentage = storageLimit > 0 and 100.00 * sellLimit / storageLimit or 100.00,
          limitOverride = sellOverride,
          price = sellPrice,
          priceOverride = sellPriceOverride,
          rule = sellRuleId,
          ruleOverride = sellOwnRule,
          ruleRoot = sellRuleRoot,
        }
      }
    end
  end

  entry.cargoCapacities = cargoCapacities

  entry.tradeData.rules = {
    buy = stationBuyRule,
    sell = stationSellRule,
  }

  entry.tradeData.rulesOverride = {
    buy = stationBuyOwnRule,
    sell = stationSellOwnRule,
  }
  entry.tradeData.waresMap = map
  return entry.tradeData
end

local function formatTradeRuleLabel(id, hasOwn, root)
  ensureTradeRuleNames()
  if id == 0 then
    id = -1
  end
  local label = tradeRuleNames and tradeRuleNames[id]
  if not label or label == "" then
    label = string.format("Rule %s", tostring(id))
  end
  if hasOwn == false then
    label = label .. " (" .. tradeRulesRoots[root or "global"] .. ")"
  end
  return label
end

local function tradeRulesDropdownOptions(isBuy, tradeData)
  ensureTradeRuleNames()
  local options = {}
  if tradeRuleNames and #tradeRuleNames > 0 then
    for ruleId, ruleName in pairs(tradeRuleNames) do
      local displayName = ruleName
      local area = ""
      if isBuy and ruleId == tradeData.rules.buy or not isBuy and ruleId == tradeData.rules.sell then
        area = tradeRulesRoots[(isBuy and tradeData.rulesOverride.buy or tradeData.rulesOverride.sell) and "station" or "global"]
      elseif C.IsPlayerTradeRuleDefault(ruleId, "buy") and C.IsPlayerTradeRuleDefault(ruleId, "sell") then
        area = tradeRulesRoots["global"]
      end
      options[#options + 1] = { id = ruleId, icon = "", text = displayName, text2 = area, displayremoveoption = false }
    end
  end
  return options
end

local function formatNumber(value, override)
  if not override then
    return texts.auto
  end
  return ConvertIntegerString(value, true, 12, true)
end

local function formatNumberWithPercentage(limit, percentage, override)
  if not override then
    return texts.auto
  end
  return ConvertIntegerString(limit, true, 12, true) .. " (" .. string.format("%05.2f%%", percentage) .. ")"
end

local function formatPrice(value, override)
  if not override then
    return texts.auto
  end
  local amount = ConvertMoneyString(value, true, true, 2, true)
  return amount
end

local function optionsNumber(override)
  if override then
    return { halign = "right" }
  end
  return { halign = "center", color = Color["text_inactive"] }
end

local function optionsRule(override)
  if override then
    return { halign = "left" }
  end
  return { halign = "left", color = Color["text_inactive"] }
end


local function sortWareList(a, b)
  local oa = wareTypeSortOrder[a.type]
  local ob = wareTypeSortOrder[b.type]
  if oa ~= ob then return oa < ob end
  return a.name < b.name
end

local function getWareList(stationData)
  local union = {}
  local list = {}
  if stationData then
    for ware, info in pairs(stationData.waresMap) do
      union[ware] = true
      list[#list + 1] = { ware = ware, name = info.name, type = info.type }
    end
  end
  table.sort(list, sortWareList)
  return list
end

local function reInitData(cloneOnly)
  if type(menu) ~= "table" then
    debugTrace("TradesEditor: reInitData: Invalid menu instance")
    return
  end
  if menu.contextMenuData == nil then
    menu.contextMenuData = {}
  end
  local data = menu.contextMenuData
  data.clone = {}
  data.clone.wares = {}
  data.clone.types = {}
  data.clone.wholeStation = false
  data.clone.confirmed = false
  if cloneOnly then
    return
  end
  data.content = {}
  data.waresStartIndex = 1
  data.waresCountTotal = 0
end

local function applyClone(menu, leftToRight)
  local data = menu.contextMenuData
  if not data then
    return
  end
  local stationOneEntry = data.selectedStationOne and data.stations[data.selectedStationOne]
  local stationTwoEntry = data.selectedStationTwo and data.stations[data.selectedStationTwo]
  if not stationOneEntry or not stationTwoEntry then
    data.statusMessage = texts.statusNoStationSelected
    data.statusColor = Color["text_warning"]
    return
  end
  local sourceEntry = leftToRight and stationOneEntry or stationTwoEntry
  local targetEntry = leftToRight and stationTwoEntry or stationOneEntry

  local sourceData = collectTradeData(sourceEntry)
  local targetData = collectTradeData(targetEntry)
  local toClone = data.clone.wares
  if toClone == nil or data.clone.confirmed ~= true then
    data.statusMessage = texts.statusNoWaresAvailable
    data.statusColor = Color["text_warning"]
    return
  end

  local skipped = {}
  local processedWaresCount = 0
  for ware, parts in pairs(toClone) do
    local sourceWareData = sourceData.waresMap[ware]
    local targetWareData = targetData.waresMap[ware]
    if (sourceWareData or targetWareData) and (parts.storage or parts.buy or parts.sell) then
      if not sourceWareData and not (parts.storage and parts.buy and parts.sell) then
        debugTrace("Skipping ware " .. tostring(ware) .. " as it is not present in source station and not fully selected for removal")
        skipped[#skipped + 1] = targetWareData.name or ware
      elseif not sourceWareData and (parts.storage and parts.buy and parts.sell) then
        debugTrace("Removing ware " .. tostring(ware) .. " from target station as it is not present in source station")
        if targetData.storageLimitOverride then
          debugTrace("Clearing storage limit override for ware " .. tostring(ware) .. " on target station")
          ClearContainerStockLimitOverride(targetEntry.id64, ware)
        end
        if targetWareData.buy.allowed then
          debugTrace("Removing buy offer for ware " .. tostring(ware) .. " on target station")
          C.ClearContainerBuyLimitOverride(targetEntry.id64, ware)
          C.SetContainerWareIsBuyable(targetEntry.id64, ware, false)
          ClearContainerWarePriceOverride(targetEntry.id64, ware, true)
        end
        if targetWareData.sell.allowed then
          debugTrace("Removing sell offer for ware " .. tostring(ware) .. " on target station")
          C.ClearContainerSellLimitOverride(targetEntry.id64, ware)
          C.SetContainerWareIsSellable(targetEntry.id64, ware, false)
          ClearContainerWarePriceOverride(targetEntry.id64, ware, false)
        end
        if targetWareData.amount == 0 then
          C.RemoveTradeWare(targetEntry.id64, ware)
        end
      elseif sourceWareData and not targetWareData and not (parts.storage and parts.buy and parts.sell) then
        debugTrace("Skipping ware " .. tostring(ware) .. " as it is not present in target station and not fully selected for addition")
        skipped[#skipped + 1] = sourceWareData.name or ware
      else
        if sourceWareData and not targetWareData then
          debugTrace("Adding ware " .. tostring(ware) .. " to target station")
          C.AddTradeWare(targetEntry.id64, ware)
        end
        if parts.storage then
          if sourceWareData and not sourceWareData.storageLimitOverride and (targetWareData == nil or not targetWareData.storageLimitOverride) then
            debugTrace("Skipping storage limit clone for ware " .. tostring(ware) .. " as both source and target have no override")
          elseif sourceWareData and not sourceWareData.storageLimitOverride and targetWareData and targetWareData.storageLimitOverride then
            debugTrace("Clearing storage limit override for ware " .. tostring(ware) .. " on target station")
            ClearContainerStockLimitOverride(targetEntry.id64, ware)
          elseif sourceWareData and sourceWareData.storageLimitOverride then
            local sourceLimit = sourceWareData.storageLimit
            local transport = sourceWareData.transport
            local newLimit = 0
            if transport and targetEntry.cargoCapacities[transport] and targetEntry.cargoCapacities[transport] > 0 then
              newLimit = math.floor(sourceWareData.storageLimitPercentage * targetEntry.cargoCapacities[transport] / 100)
            end
            if newLimit > 0 then
              SetContainerStockLimitOverride(targetEntry.id64, ware, newLimit)
              debugTrace("Setting storage limit override for ware " ..
                tostring(ware) .. " on target station to " .. tostring(sourceLimit) .. " (was " .. tostring(newLimit) .. ")")
            else
              debugTrace("Skipping setting storage limit override for ware " .. tostring(ware) .. " on target station as computed limit is zero")
            end
          end
        end
        for key, value in pairs({ buy = true, sell = true }) do
          if parts[key] then
            debugTrace("Cloning " .. key .. " offer for ware " .. tostring(ware))
            if not sourceWareData[key].allowed and (targetWareData == nil or not targetWareData[key].allowed) then
              debugTrace("Skipping " .. key .. " offer clone for ware " .. tostring(ware) .. " as both source and target have no " .. key .. " offer")
            elseif not sourceWareData[key].allowed and targetWareData and targetWareData[key].allowed then
              debugTrace("Removing " .. key .. " offer for ware " .. tostring(ware) .. " on target station")
              if key == "buy" then
                C.ClearContainerBuyLimitOverride(targetEntry.id64, ware)
                C.SetContainerWareIsBuyable(targetEntry.id64, ware, false)
              else
                C.ClearContainerSellLimitOverride(targetEntry.id64, ware)
                C.SetContainerWareIsSellable(targetEntry.id64, ware, false)
              end
            else
              if sourceWareData[key].allowed and (targetWareData == nil or not targetWareData[key].allowed) then
                debugTrace("Adding " .. key .. " offer for ware " .. tostring(ware) .. " on target station")
                if key == "buy" then
                  C.SetContainerWareIsBuyable(targetEntry.id64, ware, true)
                else
                  C.SetContainerWareIsSellable(targetEntry.id64, ware, true)
                end
              end
              if not sourceWareData[key].priceOverride and targetWareData and targetWareData[key].priceOverride then
                debugTrace("Clearing " .. key .. " price override for ware " .. tostring(ware) .. " on target station")
                ClearContainerWarePriceOverride(targetEntry.id64, ware, key == "buy")
              elseif sourceWareData[key].priceOverride then
                debugTrace("Setting " ..
                  key ..
                  " price override for ware " ..
                  tostring(ware) ..
                  " on target station to " ..
                  tostring(sourceWareData[key].price) .. " (was " .. tostring(targetWareData and targetWareData[key].price or 0) .. ")")
                SetContainerWarePriceOverride(targetEntry.id64, ware, key == "buy", sourceWareData[key].price)
              end
              if not sourceWareData[key].limitOverride and targetWareData and targetWareData[key].limitOverride then
                debugTrace("Clearing " .. key .. " limit override for ware " .. tostring(ware) .. " on target station")
                if key == "buy" then
                  C.ClearContainerBuyLimitOverride(targetEntry.id64, ware)
                else
                  C.ClearContainerSellLimitOverride(targetEntry.id64, ware)
                end
              elseif sourceWareData[key].limitOverride then
                local newLimit = sourceWareData[key].limit
                if (targetWareData ~= nil) and math.abs(targetWareData[key].limitPercentage - sourceWareData[key].limitPercentage) > 0.01 then
                  newLimit = math.floor(sourceWareData[key].limitPercentage * targetWareData.storageLimit / 100)
                end
                debugTrace("Setting " ..
                  key ..
                  " limit override for ware " ..
                  tostring(ware) ..
                  " on target station to " .. tostring(newLimit) .. " (was " .. tostring(targetWareData and targetWareData[key].limit or 0) .. ")")
                if key == "buy" then
                  C.SetContainerBuyLimitOverride(targetEntry.id64, ware, newLimit)
                else
                  C.SetContainerSellLimitOverride(targetEntry.id64, ware, newLimit)
                end
              end
              if targetWareData == nil or sourceWareData[key].rule ~= targetWareData[key].rule then
                local sourceRuleId = sourceWareData[key].rule
                local targetRuleId = targetWareData and targetWareData[key].rule or 0
                debugTrace("Setting " ..
                  key ..
                  " trade rule for ware " ..
                  tostring(ware) .. " on target station to " .. tostring(sourceRuleId) .. " (was " .. tostring(targetWareData and targetRuleId or 0) .. ")")
                if sourceRuleId == sourceData.rules[key] or data.clone.wholeStation and sourceRuleId == sourceData.rules[key] then
                  debugTrace("Using station default " ..
                    key .. " trade rule for ware " .. tostring(ware) .. " on " .. tostring(data.clone.wholeStation and "source" or "target") .. " station")
                  C.SetContainerTradeRule(targetEntry.id64, -1, key, ware, false)
                else
                  debugTrace("Enforcing own " .. key .. " trade rule for ware " .. tostring(ware) .. " on target station")
                  C.SetContainerTradeRule(targetEntry.id64, sourceRuleId, key, ware, true)
                end
              end
            end
          end
        end
      end
      processedWaresCount = processedWaresCount + 1
    end
  end
  debugTrace("Processed " .. tostring(processedWaresCount) .. " wares for cloning")
  collectTradeData(targetEntry, true)
  reInitData(true)
  if #skipped > 0 then
    data.statusMessage = string.format(tostring(texts.statusSavedWithWarnings), processedWaresCount, table.concat(skipped, ", "))
    data.statusColor = Color["text_warning"]
  else
    data.statusMessage = string.format(tostring(texts.statusSuccess), processedWaresCount)
    data.statusColor = Color["text_success"]
  end
end


local function calculateOverride(overrideFromEdit, currentOverride)
  if overrideFromEdit == nil then
    return currentOverride
  end
  return overrideFromEdit
end

local function renderOffer(tableContent, data, tradeData, ware, offerType, readyToSelectWares, render)
  local row = tableContent:addRow(true)
  local wareInfo = tradeData.waresMap[ware.ware]
  local offerData = wareInfo[offerType]
  local isBuy = (offerType == "buy")
  local editOffer = data.edit.selectedWares[ware.ware] == offerType
  row[1]:createCheckBox(data.edit.selectedWares[ware.ware] == offerType, { active = readyToSelectWares or data.edit.selectedWares[ware.ware] == offerType })
  row[1].handlers.onClick = function(_, checked)
    data.edit.selectedWares[ware.ware] = checked and offerType or nil
    if not checked then
      data.edit.slider = nil
      data.edit.changed = {}
    end
    debugTrace("Set to ware " .. tostring(ware.ware) .. " " .. offerType .. " offer edit to " .. tostring(checked))
    data.edit.confirmed = false
    data.statusMessage = nil
    render()
  end
  row[2]:createText("  " .. (isBuy and texts.buyOffer or texts.sellOffer) .. ":", textCategoryProperties)
  if ((offerData == nil) or (not offerData.allowed)) and not editOffer then
    row[3]:setColSpan(9):createText(isBuy and texts.noBuyOffer or texts.noSellOffer, { halign = "center" })
    return
  end
  row[3]:createText(texts.price .. ":")
  local priceEdit = false
  if editOffer then
    local priceOverride = calculateOverride(isBuy and data.edit.changed.priceOverrideBuy or data.edit.changed.priceOverrideSell, offerData.priceOverride) or false
    row[4]:createCheckBox(not priceOverride, { active = true })
    row[4].handlers.onClick = function(_, checked)
      if isBuy then
        data.edit.changed.priceOverrideBuy = not checked
      else
        data.edit.changed.priceOverrideSell = not checked
      end
      if checked then
        data.edit.slider = nil
      end
      data.edit.confirmed = false
      debugTrace("Set to ware " .. tostring(ware.ware) .. " " .. offerType .. " offer price override edit to " .. tostring(checked))
      data.statusMessage = nil
      render()
    end
    if isBuy and data.edit.changed.priceOverrideBuy or not isBuy and data.edit.changed.priceOverrideSell then
      priceEdit = true
    end
  else
    row[4]:createText(overrideIcons[offerData.priceOverride], overrideIconsTextProperties[offerData.priceOverride])
  end
  if priceEdit then
    local currentPrice = (isBuy and data.edit.changed.priceBuy or data.edit.changed.priceSell) or offerData.price
    row[5]:createButton({ active = true }):setText(data.edit.slider and data.edit.slider.param == "price" and texts.acceptButton or formatPrice(currentPrice, true), { halign = "center" })
    row[5].handlers.onClick = function()
      if not data.edit.slider or data.edit.slider.param ~= "price" then
        data.edit.slider = { param = "price", ware = ware.ware, offerType = offerType }
        debugTrace("Activating price slider for ware " .. tostring(ware.ware) .. " " .. offerType .. " offer")
      else
        data.edit.slider = nil
        debugTrace("Deactivating price slider for ware " .. tostring(ware.ware) .. " " .. offerType .. " offer")
      end
      data.edit.confirmed = false
      data.statusMessage = nil
      render()
    end
  else
    row[5]:createText(formatPrice(offerData.price, offerData.priceOverride), optionsNumber(offerData.priceOverride))
  end
  row[6]:createText(texts.amount .. ":")
  local limitEdit = false
  if editOffer then
    local limitOverride = calculateOverride(isBuy and data.edit.changed.limitOverrideBuy or data.edit.changed.limitOverrideSell, offerData.limitOverride) or false
    row[7]:createCheckBox(not limitOverride, { active = true })
    row[7].handlers.onClick = function(_, checked)
      if isBuy then
        data.edit.changed.limitOverrideBuy = not checked
      else
        data.edit.changed.limitOverrideSell = not checked
      end
      if checked then
        data.edit.slider = nil
      end
      data.edit.confirmed = false
      debugTrace("Set to ware " .. tostring(ware.ware) .. " " .. offerType .. " offer limit override edit to " .. tostring(checked))
      data.statusMessage = nil
      render()
    end
    if isBuy and data.edit.changed.limitOverrideBuy or not isBuy and data.edit.changed.limitOverrideSell then
      limitEdit = true
    end
  else
    row[7]:createText(overrideIcons[offerData.limitOverride], overrideIconsTextProperties[offerData.limitOverride])
  end
  if limitEdit then
    local currentLimit = (isBuy and data.edit.changed.limitBuy or data.edit.changed.limitSell) or offerData.limit
    local currentLimitPercentage = wareInfo.storageLimit > 0 and 100.00 * currentLimit / wareInfo.storageLimit or 100.00
    local formattedLimit = formatNumberWithPercentage(currentLimit, currentLimitPercentage, true)
    row[8]:createButton({ active = true }):setText(data.edit.slider and data.edit.slider.param == "limit" and texts.acceptButton or formattedLimit, { halign = "center" })
    row[8].handlers.onClick = function()
      if not data.edit.slider or data.edit.slider.param ~= "limit" then
        data.edit.slider = { param = "limit", ware = ware.ware, offerType = offerType }
        debugTrace("Activating limit slider for ware " .. tostring(ware.ware) .. " " .. offerType .. " offer")
      else
        data.edit.slider = nil
        debugTrace("Deactivating limit slider for ware " .. tostring(ware.ware) .. " " .. offerType .. " offer")
      end
      data.edit.confirmed = false
      data.statusMessage = nil
      render()
    end
  else
    row[8]:createText(formatNumberWithPercentage(offerData.limit, offerData.limitPercentage, offerData.limitOverride), optionsNumber(offerData.limitOverride))
  end
  row[9]:createText(texts.rule .. ":")
  local ruleEdit = false
  if editOffer then
    local ruleOverride = calculateOverride(isBuy and data.edit.changed.ruleOverrideBuy or data.edit.changed.ruleOverrideSell, offerData.ruleOverride) or false
    row[10]:createCheckBox(not ruleOverride, { active = true })
    row[10].handlers.onClick = function(_, checked)
      if isBuy then
        data.edit.changed.ruleOverrideBuy = not checked
      else
        data.edit.changed.ruleOverrideSell = not checked
      end
      data.edit.confirmed = false
      debugTrace("Set to ware " .. tostring(ware.ware) .. " " .. offerType .. " offer rule override edit to " .. tostring(checked))
      data.statusMessage = nil
      render()
    end
    if isBuy and data.edit.changed.ruleOverrideBuy or not isBuy and data.edit.changed.ruleOverrideSell then
      ruleEdit = true
    end
  else
    row[10]:createText(overrideIcons[offerData.ruleOverride], overrideIconsTextProperties[offerData.ruleOverride])
  end
  if ruleEdit then
    local tradeRuleOptions = tradeRulesDropdownOptions(isBuy, tradeData)
    local startOption = isBuy and (data.edit.changed.ruleBuy or offerData.rule) or (data.edit.changed.ruleSell or offerData.rule)
    debugTrace("Rendering trade rule DropDown with " ..
      tostring(#tradeRuleOptions) .. " options for ware " .. tostring(ware.ware) .. " " .. offerType .. " offer")
    row[11]:createDropDown(
      tradeRuleOptions,
      {
        startOption = startOption or -1,
        active = true,
        textOverride = (#tradeRuleOptions == 0) and "No trade rules" or nil,
      }
    )
    row[11]:setTextProperties({ halign = "left" })
    row[11]:setText2Properties({ halign = "right", color = Color["text_positive"] })
    row[11].handlers.onDropDownConfirmed = function(_, id)
      if isBuy then
        data.edit.changed.ruleBuy = tonumber(id)
      else
        data.edit.changed.ruleSell = tonumber(id)
      end
      data.edit.confirmed = false
      debugTrace("Set to ware " .. tostring(ware.ware) .. " " .. offerType .. " offer rule edit to " .. tostring(id))
      data.statusMessage = nil
      render()
    end
  else
    row[11]:createText(formatTradeRuleLabel(offerData.rule, offerData.ruleOverride, offerData.ruleRoot), optionsRule(offerData.ruleOverride))
  end
  if data.edit.slider ~= nil and data.edit.slider.ware == ware.ware and data.edit.slider.offerType == offerType then
    local row = tableContent:addRow(true)
    if data.edit.slider.param == "price" then
      local currentPrice = (isBuy and data.edit.changed.priceBuy or data.edit.changed.priceSell) or offerData.price
      currentPrice = math.max(wareInfo.minPrice, math.min(wareInfo.maxPrice, currentPrice))
      row[2]:setColSpan(10):createSliderCell(
        {
          height = Helper.standardTextHeight,
          valueColor = Color["slider_value"],
          min = wareInfo.minPrice,
          max = wareInfo.maxPrice,
          start = currentPrice,
          suffix = texts.priceSuffix,
          readOnly = false,
          hideMaxValue = true,
          forceArrows = true,
        }):setText(texts.price, { halign = "left", width = Helper.scaleX(120) })
      row[2].handlers.onSliderCellChanged = function(_, value)
        if isBuy then
          data.edit.changed.priceBuy = value
        else
          data.edit.changed.priceSell = value
        end
        data.edit.confirmed = false
        debugTrace("Set to ware " .. tostring(ware.ware) .. " " .. offerType .. " offer price edit to " .. tostring(value))
        data.statusMessage = nil
        render()
      end
      -- row[2].handlers.onSliderCellActivated = function() menu.noupdate = true end
      -- row[2].handlers.onSliderCellDeactivated = function() menu.noupdate = false end
    elseif data.edit.slider.param == "limit" then
      local currentLimit = (isBuy and data.edit.changed.limitBuy or data.edit.changed.limitSell) or offerData.limit
      local max = wareInfo.storageLimit
      currentLimit = math.max(1, math.min(max, currentLimit))
      row[2]:setColSpan(10):createSliderCell(
        {
          height = Helper.standardTextHeight,
          valueColor = Color["slider_value"],
          min = 0,
          minSelect = max == 0 and 0 or 1,
          max = max,
          start = math.min(max, currentLimit),
          readOnly = false,
          hideMaxValue = true,
          forceArrows = true,
        }):setText(texts.amount, { halign = "left", width = Helper.scaleX(120) })
      row[2].handlers.onSliderCellChanged = function(_, value)
        if isBuy then
          data.edit.changed.limitBuy = value
        else
          data.edit.changed.limitSell = value
        end
        data.edit.confirmed = false
        debugTrace("Set to ware " .. tostring(ware.ware) .. " " .. offerType .. " offer limit edit to " .. tostring(value))
        data.statusMessage = nil
        render()
      end
    end
  end
end

local function countCloneSelections(data)
  local count = {
    full = 0,
    storage = 0,
    buy = 0,
    sell = 0,
  }
  if type(data) ~= "table" or type(data.clone) ~= "table" or type(data.clone.wares) ~= "table" then
    return count
  end
  for ware, parts in pairs(data.clone.wares) do
    if (parts.storage and parts.buy and parts.sell) then
      count.full = count.full + 1
    else
      if parts.storage then
        count.storage = count.storage + 1
      end
      if parts.buy then
        count.buy = count.buy + 1
      end
      if parts.sell then
        count.sell = count.sell + 1
      end
    end
  end
  return count
end

local function setMainTableColumnsWidth(tableHandle)
  local numberWidth = Helper.scaleX(140)
  local titleWidth = Helper.scaleX(80)
  local nameWidth = Helper.scaleX(120)
  local textWidth = Helper.scaleX(240)
  local width = checkboxSize
  tableHandle:setColWidth(1, checkboxSize, false)
  tableHandle:setColWidth(2, titleWidth, false)
  width = width + numberWidth
  for i = 1, 9 do
    local column = i + 2
    local columnWidth = 0
    if i % 3 == 1 then
      columnWidth = nameWidth
    elseif i % 3 == 2 then
      columnWidth = checkboxSize
    else
      columnWidth = numberWidth
      if i == 6 then
        columnWidth = math.floor(columnWidth * 1.5)
      end
      if i == 9 then
        columnWidth = textWidth
      end
    end
    width = width + columnWidth
    tableHandle:setColWidth(column, columnWidth, false)
  end
  return width
end

local function render()
  if type(menu) ~= "table" or type(Helper) ~= "table" then
    debugTrace("TradesEditor: Render: Invalid menu instance or Helper UI utilities are not available")
    return
  end
  local data = menu.contextMenuData or {}
  if data.mode ~= "station_trades_editor" then
    return
  end
  debugTrace("Rendering Station Trades Editor UI")

  Helper.removeAllWidgetScripts(menu, data.layer)

  local checkBoxWidth = Helper.scaleX(Helper.standardTextHeight)
  local frame = data.frameHandle
  if frame then
    frame.content = {}
  else
    frame = Helper.createFrameHandle(menu, {
      x = 0,
      y = 0,
      width = 0,
      layer = data.layer,
      standardButtons = { close = true },
      closeOnUnhandledClick = false,
    })
    frame:setBackground("solid", { color = Color["frame_background_black"] })
    data.frameHandle = frame
  end
  local currentY = Helper.borderSize
  local currentTableNum = 1
  local columns = 11

  local tableTop = frame:addTable(columns, { tabOrder = currentTableNum, reserveScrollBar = false, highlightMode = "off", x = Helper.borderSize, y = currentY, })
  setMainTableColumnsWidth(tableTop)

  local row = tableTop:addRow(false, { fixed = true })
  row[1]:setColSpan(columns):createText(texts.title, Helper.headerRowCenteredProperties)


  row = tableTop:addRow(true, { fixed = true })
  row[1]:setColSpan(4):createText(texts.station, Helper.headerRowCenteredProperties)
  debugTrace("Rendering station DropDown with " .. tostring(#data.stationOptions) .. " options, selected: " .. tostring(data.selectedStation))
  row[5]:setColSpan(7):createDropDown(data.stationOptions, {
    startOption = data.selectedStation or -1,
    active = #data.stationOptions > 0,
    textOverride = (#data.stationOptions == 0) and "No player stations" or nil,
  })
  row[5]:setTextProperties({ halign = "left", color = Color["text_positive"] })
  row[5]:setText2Properties({ halign = "right" })
  row[5].handlers.onDropDownConfirmed = function(_, id)
    data.selectedStation = tonumber(id)
    data.statusMessage = nil
    reInitData()
    render()
  end

  tableTop:addEmptyRow(Helper.standardTextHeight / 2, { fixed = true })

  currentY = currentY + tableTop:getFullHeight() + Helper.borderSize * 2
  currentTableNum = currentTableNum + 1

  local tableContent = frame:addTable(columns,
    { tabOrder = currentTableNum, reserveScrollBar = true, highlightMode = "on", x = Helper.borderSize, y = currentY, })
  setMainTableColumnsWidth(tableContent)

  local stationEntry = data.selectedStation and data.stations[data.selectedStation]
  local selectedCount = 0
  local activeContent = false
  if stationEntry == nil then
    debugTrace("No stations are selected")
    row = tableContent:addRow(false)
    row[2]:setColSpan(columns - 1):createText(texts.selectStationOnePrompt,
      { color = Color["text_warning"], halign = "center" })
  else
    debugTrace("Station: " .. tostring(stationEntry.displayName) .. " (" .. tostring(stationEntry.id64) .. ")")
    local stationData = collectTradeData(stationEntry)
    local wareList = getWareList(stationData)
    local readyToSelectWares = stationEntry ~= nil and #wareList > 0 and next(data.edit.selectedWares) == nil
    debugTrace("Processing " .. tostring(#wareList) .. " wares for comparison")
    local wareType = nil
    if #wareList == 0 then
      row = tableContent:addRow(false)
      row[2]:setColSpan(columns - 1):createText(texts.noWaresAvailable,
        { color = Color["text_warning"], halign = "center" })
      data.waresCountTotal = 0
      data.waresStartIndex = 1
    else
      local wareListStartIndex = data.waresStartIndex and data.waresStartIndex or 1
      if not data.waresCountTotal or data.waresCountTotal ~= #wareList then
        wareListStartIndex = 1
      end
      if (wareListStartIndex > #wareList) then
        wareListStartIndex = #wareList > data.waresOnScreenMax and (#wareList - data.waresOnScreenMax + 1) or 1
        data.waresStartIndex = wareListStartIndex
      end
      data.waresCountTotal = #wareList
      data.waresStartIndex = wareListStartIndex
      local wareListEndIndex = math.floor(math.min(wareListStartIndex + data.waresOnScreenMax - 1, #wareList))
      for i = wareListStartIndex, wareListEndIndex do
        local ware = wareList[i]
        local wareInfo = ware ~= nil and ware.ware ~= nil and stationData.waresMap[ware.ware] or nil
        if ware == nil or wareInfo == nil then
          debugTrace("Skipping ware " .. tostring(ware ~= nil and ware.ware or "unknown") .. " - no data on either station")
        else
          if wareType ~= wareInfo.type then
            wareType = wareInfo.type
            local typeRow = tableContent:addRow(true, { bgColor = Color["row_background_unselectable"] })
            if not activeContent then
              activeContent = true
            end
            if (wareType == "trade") then
              typeRow[1]:createCheckBox(data.edit.selectedType == wareType, { active = readyToSelectWares or data.edit.selectedType == wareType })
              local wType = wareType
              typeRow[1].handlers.onClick = function(_, checked)
                data.edit.selectedType = checked and wareType or nil
                debugTrace("Set to delete all wares by type " .. tostring(wType) .. " to " .. tostring(checked))
                if checked == false then
                  data.edit.selectedWares = {}
                else
                  if (i > 1) then
                    for j = i - 1, 1, -1 do
                      local w = wareList[j]
                      local info = w.ware and stationData.waresMap[w.ware]
                      if info == nil or info.type ~= wType then
                        break
                      end
                      data.edit.selectedWares[w.ware] = "ware"
                    end
                  end
                  for j = i, #wareList do
                    local w = wareList[j]
                    local info = w.ware and stationData.waresMap[w.ware]
                    if info == nil or info.type ~= wType then
                      break
                    end
                    data.edit.selectedWares[w.ware] = "ware"
                  end
                end
                data.edit.confirmed = false
                data.statusMessage = nil
                render()
              end
            end
            typeRow[2]:setColSpan(columns - 1):createText(texts[wareType],
              { font = Helper.standardFontBold, halign = "center", color = Color["equipmentmod_quality_exceptional"], minRowHeight = checkboxSize })
            typeRow[2].handlers.onClick = function()
              debugTrace("Clicked on ware type header: " .. tostring(wareType))
            end
            tableContent:addEmptyRow(Helper.standardTextHeight / 2)
          end
          local row = tableContent:addRow(true)
          row[1]:createCheckBox(data.edit.selectedWares[ware.ware] == "ware",
            { active = readyToSelectWares or data.edit.selectedType == wareType or data.edit.selectedWares[ware.ware] == "ware", })
          row[1].handlers.onClick = function(_, checked)
            debugTrace("Set ware " .. tostring(ware.ware) .. " edit to " .. tostring(checked))
            data.edit.selectedWares[ware.ware] = checked and "ware" or nil
            data.edit.confirmed = false
            data.statusMessage = nil
            if not checked then
              data.edit.slider = nil
              data.edit.changed = {}
            end
            render()
          end
          row[2]:createText(texts.ware .. ":", textCategoryProperties)
          row[3]:setColSpan(3):createText(ware.name, wareNameTextProperties)
          row[6]:setColSpan(2):createText(texts.amount .. ":")
          row[8]:createText(formatNumber(wareInfo.amount, true), cargoAmountTextProperties)
          row[9]:createText(texts.storage .. ":")
          local storageLimitEdit = false
          if data.edit.selectedType == nil and data.edit.selectedWares[ware.ware] == "ware" then
            local storageLimitOverride = calculateOverride(data.edit.changed.storageLimitOverride, wareInfo.storageLimitOverride)
            row[10]:createCheckBox(not storageLimitOverride, { active = true })
            row[10].handlers.onClick = function(_, checked)
              data.edit.changed.storageLimitOverride = not checked
              debugTrace("Set ware " .. tostring(ware.ware) .. " storage limit override new value to " .. tostring(not checked))
              data.edit.confirmed = false
              data.statusMessage = nil
              render()
            end
            if storageLimitOverride then
              storageLimitEdit = true
            end
          else
            row[10]:createText(overrideIcons[wareInfo.storageLimitOverride], overrideIconsTextProperties[wareInfo.storageLimitOverride])
          end
          if storageLimitEdit then
          else
            row[11]:createText(formatNumberWithPercentage(wareInfo.storageLimit, wareInfo.storageLimitPercentage, wareInfo.storageLimitOverride),
              optionsNumber(wareInfo.storageLimitOverride))
          end
          renderOffer(tableContent, data, stationEntry.tradeData, ware, "buy", readyToSelectWares, render)
          renderOffer(tableContent, data, stationEntry.tradeData, ware, "sell", readyToSelectWares, render)
        end
        tableContent:addEmptyRow(Helper.standardTextHeight / 2)
      end
    end
  end

  tableContent.properties.maxVisibleHeight = math.min(tableContent:getFullHeight(), data.contentHeight)
  if data.content and data.content.tableContentId then
    local topRow = GetTopRow(data.content.tableContentId)
    if topRow and topRow > 0 then
      tableContent:setTopRow(topRow)
    end
    local selectedRow = Helper.currentTableRow[data.content.tableContentId]
    if selectedRow ~= nil and selectedRow > 0 then
      tableContent:setSelectedRow(selectedRow)
    end
  end

  frame.properties.width = tableTop.properties.width + Helper.borderSize * 2
  if tableContent:hasScrollBar() and not tableContent.properties.reserveScrollBar then
    tableContent.properties.reserveScrollBar = true
    frame.properties.width = frame.properties.width + Helper.scrollbarWidth
  end

  currentY = currentY + tableContent.properties.maxVisibleHeight + Helper.borderSize
  currentTableNum = currentTableNum + 1

  if data.waresCountTotal > data.waresOnScreenMax then
    currentY = currentY + Helper.borderSize
    local pageCount = math.ceil(data.waresCountTotal / data.waresOnScreenMax)
    local currentPage = math.ceil(data.waresStartIndex / data.waresOnScreenMax)
    local pageInfoFormat = tostring(texts.pageInfo or "%d / %d")
    local pageInfoText = string.format(pageInfoFormat, currentPage, pageCount)
    local tablePages = frame:addTable(12, { tabOrder = currentTableNum, reserveScrollBar = false, highlightMode = "off", x = Helper.borderSize, y = currentY })
    tablePages:setColWidth(1, checkBoxWidth, false)
    local pageButtonWidth = 80
    local pageIntervalWidth = 30
    tablePages:setColWidthMin(2, pageButtonWidth, 2, true)
    for i = 3, 11 do
      if i % 2 == 0 then
        tablePages:setColWidth(i, pageIntervalWidth, false)
      elseif i == 7 then
        tablePages:setColWidth(i, pageButtonWidth + pageIntervalWidth, false)
      else
        tablePages:setColWidth(i, pageButtonWidth, false)
      end
    end
    tablePages:setColWidthMin(12, pageButtonWidth, 2, true)
    local row = tablePages:addRow(true, { fixed = true })
    row[3]:createButton({ active = currentPage > 1 }):setText("\27[widget_arrow_left_01]\27X\27[widget_arrow_left_01]\27X", { halign = "center" })
    row[3].handlers.onClick = function()
      data.waresStartIndex = 1
      render()
    end

    row[5]:createButton({ active = currentPage > 1 }):setText("\27[widget_arrow_left_01]\27X", { halign = "center" })
    row[5].handlers.onClick = function()
      data.waresStartIndex = math.max(1, data.waresStartIndex - data.waresOnScreenMax)
      render()
    end

    row[7]:createText(pageInfoText, { halign = "center" })

    row[9]:createButton({ active = currentPage < pageCount }):setText("\27[widget_arrow_right_01]\27X", { halign = "center" })
    row[9].handlers.onClick = function()
      if currentPage < pageCount then
        data.waresStartIndex = data.waresStartIndex + data.waresOnScreenMax
      end
      render()
    end

    row[11]:createButton({ active = currentPage < pageCount }):setText("\27[widget_arrow_right_01]\27X\27[widget_arrow_right_01]\27X", { halign = "center" })
    row[11].handlers.onClick = function()
      data.waresStartIndex = (pageCount - 1) * data.waresOnScreenMax + 1
      render()
    end

    currentY = currentY + tablePages:getFullHeight() + Helper.borderSize
    currentTableNum = currentTableNum + 1
  end

  local tableConfirm = frame:addTable(9,
    { tabOrder = currentTableNum, reserveScrollBar = false, highlightMode = "off", x = Helper.borderSize, y = currentY })
  local cellWidth = math.floor((tableTop.properties.width - checkBoxWidth) / 8) - 3
  for i = 1, 3 do
    tableConfirm:setColWidth(i, cellWidth, false)
  end
  tableConfirm:setColWidth(4, checkBoxWidth, false)
  for i = 5, 9 do
    tableConfirm:setColWidth(i, cellWidth, false)
  end

  tableConfirm:addEmptyRow(Helper.standardTextHeight / 2)
  row = tableConfirm:addRow(true, { fixed = true })

  row[4]:createCheckBox(data.edit.confirmed, { active = next(data.edit.selectedWares) ~= nil })
  row[4].handlers.onClick = function(_, checked)
    data.edit.confirmed = checked
    debugTrace("Set edit confirmed to " .. tostring(checked))
    data.statusMessage = nil
    render()
  end
  row[5]:setColSpan(2):createText(texts.confirmSave, { halign = "left" })

  currentY = currentY + tableConfirm:getFullHeight() + Helper.borderSize * 2
  currentTableNum = currentTableNum + 1


  local tableBottom = frame:addTable(8,
    { tabOrder = currentTableNum, reserveScrollBar = false, highlightMode = "off", x = Helper.borderSize, y = currentY })

  tableBottom:setColWidth(1, checkBoxWidth, false)
  local buttonWidth = math.floor((tableTop.properties.width - checkBoxWidth) / 7) - 3
  for i = 2, 8 do
    tableBottom:setColWidth(i, buttonWidth, false)
  end

  row = tableBottom:addRow(true, { fixed = true })

  -- row[4]:createButton({ active = selectedCount > 0 and data.clone.confirmed }):setText(texts.cloneButton .. "  \27[widget_arrow_right_01]\27X",
  --   { halign = "center" })
  -- row[4].handlers.onClick = function()
  --   if selectedCount > 0 then
  --     applyClone(menu, true)
  --     render()
  --   end
  -- end
  row[6]:createButton({ active = next(data.edit.selectedWares) ~= nil and data.edit.confirmed }):setText(texts.saveButton,
    { halign = "center" })
  row[6].handlers.onClick = function()
    if selectedCount > 0 then
      applyClone(menu, false)
      render()
    end
  end
  row[8]:createButton({}):setText(texts.cancelButton, { halign = "center" })
  row[8].handlers.onClick = function()
    menu.closeContextMenu()
  end

  local cloneCounts = countCloneSelections(data)
  if cloneCounts and (cloneCounts.full + cloneCounts.storage + cloneCounts.buy + cloneCounts.sell > 0) then
    data.statusMessage = string.format(tostring(texts.statusSelectionInfo or ""),
      tostring(cloneCounts.full),
      tostring(cloneCounts.storage),
      tostring(cloneCounts.buy),
      tostring(cloneCounts.sell))
    data.statusColor = Color["text_inactive"]
  end

  if data.statusMessage then
    local statusRow = tableBottom:addRow(false, { fixed = true })
    statusRow[1]:setColSpan(8):createText(data.statusMessage, { wordwrap = true, color = data.statusColor })
  end
  tableBottom:setSelectedCol(8)

  frame.properties.height = currentY + tableBottom:getFullHeight() + Helper.borderSize

  frame.properties.y = math.floor((Helper.viewHeight - frame.properties.height) / 2)
  frame.properties.x = math.floor((Helper.viewWidth - frame.properties.width) / 2)

  frame:display()
  data.content = {}
  data.content.tableTopId = tableTop.id
  data.content.tableContentId = tableContent.id
  data.content.tableConfirmId = tableConfirm.id
  data.content.tableBottomId = tableBottom.id
  data.frame = frame
  menu.contextFrame = frame
end

local function getArgs()
  if playerId == 0 then
    debugTrace("getArgs unable to resolve player id")
  else
    local list = GetNPCBlackboard(playerId, "$StationTradesEditorSelected")
    if type(list) == "table" then
      debugTrace("getArgs retrieved " .. tostring(#list) .. " entries from blackboard")
      local args = list[#list]
      SetNPCBlackboard(playerId, "$StationTradesEditorSelected", nil)
      return args
    elseif list ~= nil then
      debugTrace("getArgs received non-table payload of type " .. type(list))
    else
      debugTrace("getArgs found no blackboard entries for player " .. tostring(playerId))
    end
  end
  return nil
end

local function show()
  debugTrace("Show called")
  if type(menu) ~= "table" or type(Helper) ~= "table" then
    debugTrace("Show: Invalid menu instance or Helper UI utilities are not available")
    return
  end


  if type(menu) ~= "table" or type(menu.closeContextMenu) ~= "function" then
    return false, "Menu instance is not available"
  end
  if type(Helper) ~= "table" then
    return false, "Helper UI utilities are not available"
  end

  menu.closeContextMenu()

  local data = {
    mode = "station_trades_editor",
    layer = menu.contextFrameLayer or 2,
    contentHeight = math.floor(Helper.viewHeight * 0.6),
    waresOnScreenMax = 30,
    edit = {
      selectedWares = {},
      selectedType = nil,
      changed = {},
      slider = nil,
      confirmed = false,
    },
  }

  data.stations, data.stationOptions = buildStationCache()

  data.selectedStation = nil

  local args = getArgs()
  if args and type(args) == "table" and args.selectedStation then
    if args.selectedStation then
      local selectedStationId = ConvertStringTo64Bit(tostring(args.selectedStation))
      debugTrace("Pre-selecting station " .. tostring(selectedStationId) .. " as working station")
      if data.stations[selectedStationId] then
        data.selectedStation = selectedStationId
      else
        debugTrace("Pre-selected station " .. tostring(selectedStationId) .. " not found in player stations")
      end
    end
  end


  menu.contextMenuMode = data.mode
  menu.contextMenuData = data

  reInitData()
  render()

  return true
end

local function getPlayerId()
  local current = C.GetPlayerID()
  if current == nil or current == 0 then
    return
  end

  local converted = ConvertStringTo64Bit(tostring(current))
  if converted ~= 0 and converted ~= playerId then
    debugTrace("updating player_id to " .. tostring(converted))
    playerId = converted
  end
end

local function Init()
  getPlayerId()
  ---@diagnostic disable-next-line: undefined-global
  RegisterEvent("StationTradesEditorShow", show)
  menu = Lib.Get_Egosoft_Menu("MapMenu")
  debugTrace("MapMenu is " .. tostring(menu))
end

Register_Require_With_Init("extensions.station_trades_editor.ui.station_trades_editor", nil, Init)
