--[[
   Copyright 2023 HappyGnome (https://github.com/HappyGnome)

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
--]]

local DbOption      = require("Options.DbOption")
local DialogLoader	= require('DialogLoader')
local lfs		    = require('lfs')
local ListBoxItem	= require('ListBoxItem')
local MsgWindow 	= require('MsgWindow')

local webhookerDir = lfs.writedir()..[[Mods\Services\Webhooker]]

package.path = package.path  .. ";" .. webhookerDir .. "\\core\\?.lua;"

require("Webhooker_logging")
Webhooker.Logging.changeFile([[Webhooker.options.log]])

require("Webhooker_server")

Webhooker.Server.loadConfiguration()
Webhooker.Server.loadCommonMsgParts()

local webhookKeyItemMap = {}

local workingTemplate = {
    origTemplateKey = "",
    templateKey = "",
    webhookKey = "",
	bodyRaw = ""
}

local workingWebhook = {
    origWebhookKey = "",
    webhookKey = "",
	url = ""
}

local workingEditString = {key = "",value = ""}

--------------------------------------------------------------------------------------
-- TEST METHODS
--------------------------------------------------------------------------------------
local countTemplateParams = function(rawTemplate)
    local replaceIndices = {}

    if rawTemplate == nil then return 0 end

    local at = 1
    local atEnd = string.len(rawTemplate)
    while at <= atEnd do
        local found = string.find(rawTemplate,"%%", at) -- "%" (%% in lua regexp) starts replaceable token

        if found == nil then
            break
        end
        
        if string.sub(rawTemplate,found,found+1) == "%%" then
            at = found + 2
        else
            local tok = ""
            local foundEnd = string.find(rawTemplate,"[%s%%]", found + 1)
            if foundEnd  == nil then
                tok = string.sub(rawTemplate, found + 1, atEnd)
                at = atEnd + 1
            else
                tok = string.sub(rawTemplate, found + 1, foundEnd - 1)
                at = foundEnd + 1
            end

            local tokNum = tonumber(tok)

            if type(tokNum) == 'number' then
                replaceIndices[tokNum] = true
            end
        end
    end
    return #replaceIndices
end

local doTestSend = function(templateKey, args)

    if Webhooker.Server.templates[templateKey] == nil then
        error("Invalid template key: " .. templateKey)
    end
    local template = Webhooker.Server.templates[templateKey]
    
    local task = Webhooker.Server.trySendToWebhook(template.webhookKey,template.bodyRaw,args)
    task:Await(1000)
end

Webhooker.send = function(templateKey, ...) 
    Webhooker.Server.ensureLuaWorker()

    local ok,err = pcall(doTestSend,templateKey, arg)

    if Webhooker.Server.worker ~= nil then
		Webhooker.Server.worker:Stop()	
    end

    if not ok then
        error(err)
    end
end

Webhooker.func = function(funcKey, ...)
    return "<" .. funcKey .. " result>"
end

Webhooker.string = function(stringKey)
    return Webhooker.Server.strings[stringKey]
end

Webhooker.player = function(playerKey)
    return playerKey
end

--------------------------------------------------------------------------------------
-- WIDGET HELPERS
--------------------------------------------------------------------------------------

local resetComboListFromTable = function(cmb,tbl)

    if not cmb or not tbl then return end

    ret = {}

    cmb:clear()
    local first = true
    for k,v in pairs(tbl) do
        local item = ListBoxItem.new(_(k))
        item.type = "any"
        cmb:insertItem(item)

        ret[k] = item

        if first then cmb:selectItem(item) end
        first = false
    end 
    return ret
end

local resetKVGridFromTable = function(grid,tbl,skins)

    if not grid or not tbl then return end

    local sorted = {}

    for k,v in pairs(tbl) do
        sorted[#sorted + 1] = {k,v}
    end

    table.sort(sorted,function(a,b) return string.upper(a[1]) < string.upper(b[1]) end)

    grid:clearRows()

    local row = 0
    for i,v in ipairs(sorted) do
        grid:insertRow(20)
        local col = 1

        -- Col 1
        local cell = Static.new(v[col])
        if skins and skins[col] then cell:setSkin(skins[col]) end

        grid:setCell(col-1,row,cell)

        col = col + 1
        --Col 2
        cell = Static.new(v[col])
        if skins and skins[col] then cell:setSkin(skins[col]) end
        grid:setCell(col-1,row,cell)

        row = row + 1
    end 
end

--------------------------------------------------------------------------------------
-- NAVIGATION
--------------------------------------------------------------------------------------

local GoPageTemplateEdit = function(dialog)
    dialog.pnlTemplateEdit.edtName:setText(workingTemplate.templateKey)
    if webhookKeyItemMap[workingTemplate.webhookKey] ~= nil then        
        dialog.pnlTemplateEdit.cmbWebhook:selectItem(webhookKeyItemMap[workingTemplate.webhookKey])
    end
    dialog.pnlTemplateEdit.edtBody:setText(workingTemplate.bodyRaw)
    dialog.pnlTemplateEdit.lblNameWarn:setVisible(false)
    dialog.pnlTemplateEdit.lblWebhookWarn:setVisible(false)

    dialog.pnlTemplateEdit:setVisible(true)
    dialog.pnlTemplateSelect:setVisible(false)
    dialog.pnlWebhookEdit:setVisible(false)
    dialog.pnlStringList:setVisible(false)
    dialog.pnlStringEdit:setVisible(false)
    dialog.pnlTemplateTest:setVisible(false)
end

local GoPageTemplateSelect = function(dialog)
    dialog.pnlTemplateEdit:setVisible(false)
    dialog.pnlTemplateSelect:setVisible(true)
    dialog.pnlWebhookEdit:setVisible(false)
    dialog.pnlStringList:setVisible(false)
    dialog.pnlStringEdit:setVisible(false)
    dialog.pnlTemplateTest:setVisible(false)
end

local GoPageWebhookEdit = function(dialog)
    dialog.pnlWebhookEdit.edtWebhook:setText(workingWebhook.webhookKey)
    dialog.pnlWebhookEdit.edtUrl:setText(workingWebhook.url)

    dialog.pnlWebhookEdit.lblWebhookWarn:setVisible(false)

    dialog.pnlTemplateEdit:setVisible(false)
    dialog.pnlTemplateSelect:setVisible(false)
    dialog.pnlWebhookEdit:setVisible(true)
    dialog.pnlStringList:setVisible(false)
    dialog.pnlStringEdit:setVisible(false)
    dialog.pnlTemplateTest:setVisible(false)
end

local GoPageStringsManage = function(dialog)

    dialog.pnlTemplateEdit:setVisible(false)
    dialog.pnlTemplateSelect:setVisible(false)
    dialog.pnlWebhookEdit:setVisible(false)
    dialog.pnlStringList:setVisible(true)
    dialog.pnlStringEdit:setVisible(true)
    dialog.pnlTemplateTest:setVisible(false)
end

local GoPageTest = function(dialog)

    dialog.pnlTemplateEdit:setVisible(false)
    dialog.pnlTemplateSelect:setVisible(false)
    dialog.pnlWebhookEdit:setVisible(false)
    dialog.pnlStringList:setVisible(false)
    dialog.pnlStringEdit:setVisible(false)
    dialog.pnlTemplateTest:setVisible(true)
end

local GoStringEditMode = function(dialog,edit)

    dialog.pnlStringEdit:setEnabled(edit)
    dialog.pnlStringList:setEnabled(not edit)
end

local RequestConfirm = function(actionYes, text, actionNo)
    local optYes = "YES"
    local optNo = "NO"

    local handler = MsgWindow.question(_(text), _('WARNING'), optYes, optNo)
    function handler:onChange(btnTxt)
        if btnTxt == optYes then
            if actionYes ~= nil then
                actionYes()
            end
        elseif actionNo ~= nil then
            actionNo()
        end
        handler:close()
    end

    handler:show()
end

local DenyMsgBox = function(text)
    local optOK = "OK"

    local handler = MsgWindow.question(_(text), _('WARNING'), optOK)
    function handler:onChange(btnTxt)
        handler:close()
    end

    handler:show()
end

local StashWorkingTemplate = function(dialog)
    local webhookItem = dialog.pnlTemplateEdit.cmbWebhook:getSelectedItem()
    if webhookItem ~= nil then
        workingTemplate.webhookKey = webhookItem:getText()
    end

    workingTemplate.templateKey = dialog.pnlTemplateEdit.edtName:getText()
    
    workingTemplate.bodyRaw = dialog.pnlTemplateEdit.edtBody:getText()
end

local ResetTemplateListCombo = function(dialog)
    resetComboListFromTable(dialog.pnlTemplateSelect.cmbTemplate,Webhooker.Server.templates)
end

local ResetWebhookListCombo = function(dialog)
    webhookKeyItemMap = resetComboListFromTable(dialog.pnlTemplateEdit.cmbWebhook,Webhooker.Server.webhooks)
end

local ResetStringGrid = function(dialog)
    resetKVGridFromTable(
        dialog.pnlStringList.gridStrings,
        Webhooker.Server.strings, 
        {dialog.pnlStringList.staticGridCell:getSkin(),dialog.pnlStringList.staticGridCell:getSkin()})
end

local ClearStringSelection = function(dialog)
    workingEditString = {key = "",value = ""}
    dialog.pnlStringList.gridStrings:selectRow(-1)
    dialog.pnlStringList.btnStringEdit:setEnabled(false)
end
--------------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------------

local handleTemplateAdd = function(dialog)
    
    workingTemplate = {
        origTemplateKey = "",
        templateKey = "",
        webhookKey = "",
        bodyRaw = ""
    }

    RequestConfirm(
        function() 
            workingTemplate.bodyRaw = 
[[{
    "username":"ExampleBot",
    "content":"Message text"
}]]
            GoPageTemplateEdit(dialog) 
        end,
        "Add Discord webhook example?",
        function() 
            GoPageTemplateEdit(dialog) 
        end)

    
end

local resetWorkingTemplate = function(dialog)
    local item = dialog.pnlTemplateSelect.cmbTemplate:getSelectedItem()

    if item ~= nil then
        local templateKey = item:getText()
        local templateOrig = Webhooker.Server.templates[templateKey]
        workingTemplate = 
        {
            bodyRaw = templateOrig.bodyRaw,
            webhookKey = templateOrig.webhookKey,
            origTemplateKey = templateKey,
            templateKey = templateKey
        }

        return true
    end

    return false
end

local handleTemplateEdit = function(dialog)
    if resetWorkingTemplate(dialog) then
        GoPageTemplateEdit(dialog)
    end
end

local handleTemplateTest = function(dialog)
    resetWorkingTemplate(dialog)
    
    GoPageTest(dialog)
end

local handleTemplateDelete = function(dialog)

    local item = dialog.pnlTemplateSelect.cmbTemplate:getSelectedItem()

    if item ~= nil then
        Webhooker.Server.templates[item:getText()] = nil
        Webhooker.Server.saveConfiguration()
        ResetTemplateListCombo(dialog)
    end
end

local handleTemplateCancel = function(dialog)
    GoPageTemplateSelect(dialog)
end

local handleTemplateSave = function(dialog)
    
    local webhookItem = dialog.pnlTemplateEdit.cmbWebhook:getSelectedItem()
    if webhookItem == nil then
        dialog.pnlTemplateEdit.lblWebhookWarn:setVisible(true)
        return
    end

    StashWorkingTemplate(dialog)

    if workingTemplate.templateKey == nil or workingTemplate.templateKey =="" or 
        (workingTemplate.templateKey ~= workingTemplate.origTemplateKey and Webhooker.Server.templates[workingTemplate.templateKey] ~=nil) then
        dialog.pnlTemplateEdit.lblNameWarn:setVisible(true)
        return
    end

    Webhooker.Server.templates[workingTemplate.templateKey] = {
        webhookKey = workingTemplate.webhookKey,
        bodyRaw = workingTemplate.bodyRaw
    }

    Webhooker.Server.saveConfiguration()

    ResetTemplateListCombo(dialog)
    GoPageTemplateSelect(dialog)
end

local handleWebhookAdd = function(dialog)

    StashWorkingTemplate(dialog)
    workingWebhook = {
        origWebhookKey = "",
        webhookKey = "",
        url = ""
    }

    GoPageWebhookEdit(dialog)
end

local handleWebhookEdit = function(dialog)

    StashWorkingTemplate(dialog)

    local item = dialog.pnlTemplateEdit.cmbWebhook:getSelectedItem()

    if item ~= nil then
        local webhookKey = item:getText()
        workingWebhook = 
        {
            url = Webhooker.Server.webhooks[webhookKey],
            origWebhookKey = webhookKey,
            webhookKey = webhookKey
        }

        GoPageWebhookEdit(dialog)
    end    
end

local handleWebhookDelete = function(dialog)
    local item = dialog.pnlTemplateEdit.cmbWebhook:getSelectedItem()

    if item ~= nil then
        Webhooker.Server.webhooks[item:getText()] = nil
        Webhooker.Server.saveConfiguration()
        ResetWebhookListCombo(dialog)
    end
end

local handleWebhookCancel = function(dialog)
    GoPageTemplateEdit(dialog)
end

local handleWebhookSave = function(dialog)

    workingWebhook.webhookKey = dialog.pnlWebhookEdit.edtWebhook:getText()
    workingWebhook.url = dialog.pnlWebhookEdit.edtUrl:getText()    

    if workingWebhook.webhookKey == nil or workingWebhook.webhookKey == "" or 
        (workingWebhook.webhookKey ~= workingWebhook.origWebhookKey 
            and Webhooker.Server.webhooks[workingWebhook.webhookKey] ~= nil) then
        dialog.pnlWebhookEdit.lblWebhookWarn:setVisible(true)
        return
    end

    Webhooker.Server.webhooks[workingWebhook.webhookKey] = workingWebhook.url

    ResetWebhookListCombo(dialog)

    Webhooker.Server.saveConfiguration()

    GoPageTemplateEdit(dialog)
end

--String list
local handleStringListSelect = function(dialog,row)
    if row == nil or row < 0 then 
        dialog.pnlStringList.btnStringEdit:setEnabled(false)
        return 
    end

    dialog.pnlStringList.gridStrings:selectRow(row)

    local cell = dialog.pnlStringList.gridStrings:getCell(0,row)
    workingEditString.key = cell:getText()

    cell = dialog.pnlStringList.gridStrings:getCell(1,row)
    workingEditString.value = cell:getText()

    dialog.pnlStringList.btnStringEdit:setEnabled(true)
end

local handleStringListNew = function(dialog)

    dialog.pnlStringEdit.edtKey:setText("")
    dialog.pnlStringEdit.edtString:setText("")
    ClearStringSelection(dialog)

    GoStringEditMode(dialog,true)
end

local handleStringListEdit = function(dialog)

    dialog.pnlStringEdit.edtKey:setText(workingEditString.key)
    dialog.pnlStringEdit.edtString:setText(workingEditString.value)

    GoStringEditMode(dialog,true)
end

local handleStringListDel = function(dialog)

    local newKey = workingEditString.key

    if newKey == nil then return end

    local onSuccess = function()        
        Webhooker.Server.strings[newKey] = nil
        Webhooker.Server.saveConfiguration()

        ResetStringGrid(dialog)
        ClearStringSelection(dialog)
    end

    RequestConfirm(onSuccess,"Delete string for key \"" .. newKey .. "\"")
end

local handleStringListCancel = function(dialog)
    GoPageTemplateSelect(dialog)
end

-- String edit
local handleStringEditSubmit = function(dialog)

    local newKey = dialog.pnlStringEdit.edtKey:getText()
    local newValue = dialog.pnlStringEdit.edtString:getText()

    if (newKey == nil or newKey == "") then
        DenyMsgBox("Key invalid")
        return
    end

    local onSuccess = function()        
        Webhooker.Server.strings[newKey] = newValue
        Webhooker.Server.saveConfiguration()

        GoStringEditMode(dialog,false)
        dialog.pnlStringEdit.edtKey:setText("")
        dialog.pnlStringEdit.edtString:setText("")
        ResetStringGrid(dialog)
    end

    if (newKey ~= workingEditString.key and Webhooker.Server.strings[newKey] ~= nil) then
        RequestConfirm(onSuccess,"Replace existing string for key \"" .. newKey .. "\"")
        return
    end

    onSuccess()

end

local handleStringEditCancel = function(dialog)
    GoStringEditMode(dialog,false)
end

-- Template Test

local handleTestSend = function (dialog) 
    local ok,err = pcall(loadstring(dialog.pnlTemplateTest.edtTestScript:getText()))

    if not ok then 
        DenyMsgBox("Error in script: " .. err)
    end

    if Webhooker.Server.worker ~= nil then
        local strOut = ""
        for i = 1,100 do
            local s = Webhooker.Server.worker:PopLogLine() 
            if s == nil then break end
            strOut = strOut .. s .. "\r\n"	
        end
        dialog.pnlTemplateTest.edtTestLogOutput:setText(strOut)
    end
end

local handleTestCancel = function (dialog) 
    GoPageTemplateSelect(dialog)
end

local randomReplaceString = function()

    local funcInd = math.random(1,2)
    
    if funcInd == 1 then
        local stringHat = {}
        for k,v in pairs(Webhooker.Server.strings) do
            stringHat[#stringHat + 1] = k
        end

        return "string",stringHat[math.random(1,#stringHat)]
    else
        return "player","Player" .. math.random(1,99)
    end
end

local handleTestExample = function (dialog) 

    local templateKey = workingTemplate.origTemplateKey

    local templateParamCount = 0

    if Webhooker.Server.templates[templateKey] ~= nil then
        templateParamCount = countTemplateParams(Webhooker.Server.templates[templateKey].bodyRaw)
    end

    local demoString = [[Webhooker.send("]] .. templateKey .. [["]]

    for i = 1,templateParamCount do
        local randomFunc,randomKey = randomReplaceString()
        demoString = demoString .. [[, Webhooker.]] .. randomFunc .. [[("]] .. randomKey .. [[")]]
    end

    demoString = demoString .. [[)]]

    dialog.pnlTemplateTest.edtTestScript:setText(demoString)
end
--------------------------------------------------------------------------------------
-- CALLBACKS
--------------------------------------------------------------------------------------
local showDialog = function(dialog)
    if dialog == nil then return end

    -- Template select controls
    function dialog.pnlTemplateSelect.btnTemplateAdd:onChange() handleTemplateAdd(dialog) end

    function dialog.pnlTemplateSelect.btnTemplateEdit:onChange() handleTemplateEdit(dialog) end
    
    function dialog.pnlTemplateSelect.btnStringsManage:onChange() GoPageStringsManage(dialog) end
    function dialog.pnlTemplateSelect.btnTemplateTest:onChange() handleTemplateTest(dialog) end
       
    function dialog.pnlTemplateSelect.btnTemplateDel:onChange() 
            RequestConfirm(function() handleTemplateDelete(dialog) end, "Delete template?")
    end   

    -- Template edit controls
    function dialog.pnlTemplateEdit.btnCancelTemplate:onChange() handleTemplateCancel(dialog) end

    function dialog.pnlTemplateEdit.btnSaveTemplate:onChange() handleTemplateSave(dialog) end
    function dialog.pnlTemplateEdit.btnWebhookAdd:onChange() handleWebhookAdd(dialog) end
    function dialog.pnlTemplateEdit.btnWebhookEdit:onChange() handleWebhookEdit(dialog) end
    function dialog.pnlTemplateEdit.btnWebhookDel:onChange() 
            RequestConfirm(function() handleWebhookDelete(dialog) end,"Delete webhook?")
    end

    -- Webhook edit controls
    function dialog.pnlWebhookEdit.btnWebhookCancel:onChange() handleWebhookCancel(dialog) end
    function dialog.pnlWebhookEdit.btnWebhookSave:onChange() handleWebhookSave(dialog) end


    -- String list
    function dialog.pnlStringList.gridStrings:onMouseDown(x,y,btn)
        if btn == 1 then
            local col, row = self:getMouseCursorColumnRow(x,y)

            if row >= 0 then
                handleStringListSelect(dialog,row)
            end
        end
    end

    function dialog.pnlStringList.btnStringNew:onChange() handleStringListNew(dialog) end
    function dialog.pnlStringList.btnStringEdit:onChange() handleStringListEdit(dialog) end
    function dialog.pnlStringList.btnStringDel:onChange() handleStringListDel(dialog) end
    function dialog.pnlStringList.btnStringCancel:onChange() handleStringListCancel(dialog) end

    --String edit
    function dialog.pnlStringEdit.btnStringSubmit:onChange() handleStringEditSubmit(dialog) end
    function dialog.pnlStringEdit.btnStringCancel:onChange() handleStringEditCancel(dialog) end

    -- Template Test
    function dialog.pnlTemplateTest.btnTestSend:onChange() handleTestSend(dialog) end
    function dialog.pnlTemplateTest.btnTestCancel:onChange() handleTestCancel(dialog) end
    function dialog.pnlTemplateTest.btnTestExample:onChange() handleTestExample(dialog) end

    -- Initialize lists
    
    ResetWebhookListCombo(dialog)
    ResetTemplateListCombo(dialog)
    ResetStringGrid(dialog)

end

--------------------------------------------------------------------------------------
-- RETURN
--------------------------------------------------------------------------------------
return {
    callbackOnShowDialog  = showDialog
}