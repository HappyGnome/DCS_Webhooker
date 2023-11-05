local DbOption = require("Options.DbOption")
local DialogLoader		= require('DialogLoader')
local lfs		= require('lfs')
local ListBoxItem		= require('ListBoxItem')

local webhookerDir = lfs.writedir()..[[Mods\Services\DCS_Webhooker]]

dofile(webhookerDir .. [[\core\Webhooker_server.lua]])

Webhooker.Server.reloadTemplates()
Webhooker.Server.loadConfiguration()

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
end

local GoPageTemplateSelect = function(dialog)
    dialog.pnlTemplateEdit:setVisible(false)
    dialog.pnlTemplateSelect:setVisible(true)
    dialog.pnlWebhookEdit:setVisible(false)
end

local GoPageWebhookEdit = function(dialog)
    dialog.pnlWebhookEdit.edtWebhook:setText(workingWebhook.webhookKey)
    dialog.pnlWebhookEdit.edtUrl:setText(workingWebhook.url)

    dialog.pnlWebhookEdit.lblWebhookWarn:setVisible(false)

    dialog.pnlTemplateEdit:setVisible(false)
    dialog.pnlTemplateSelect:setVisible(false)
    dialog.pnlWebhookEdit:setVisible(true)
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
    webhookKeyItemMap = resetComboListFromTable(dialog.pnlTemplateSelect.cmbTemplate,Webhooker.Server.templates)
end

local ResetWebhookListCombo = function(dialog)
    resetComboListFromTable(dialog.pnlTemplateEdit.cmbWebhook,Webhooker.Server.webhooks)
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

    GoPageTemplateEdit(dialog)
end

local handleTemplateEdit = function(dialog)
    
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

        GoPageTemplateEdit(dialog)
    end
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

--------------------------------------------------------------------------------------
-- CALLBACKS
--------------------------------------------------------------------------------------
local showDialog = function(dialog)
    if dialog == nil then return end

    -- Template select controls
    if dialog.pnlTemplateSelect.btnTemplateAdd then
        function dialog.pnlTemplateSelect.btnTemplateAdd:onChange() handleTemplateAdd(dialog) end
    end

    if dialog.pnlTemplateSelect.btnTemplateEdit then
        function dialog.pnlTemplateSelect.btnTemplateEdit:onChange() handleTemplateEdit(dialog) end
    end

    if dialog.pnlTemplateSelect.btnTemplateDel then
        function dialog.pnlTemplateSelect.btnTemplateDel:onChange() handleTemplateDelete(dialog) end
    end

    -- Template edit controls
    if dialog.pnlTemplateEdit.btnCancelTemplate then
        function dialog.pnlTemplateEdit.btnCancelTemplate:onChange() handleTemplateCancel(dialog) end
    end

    if dialog.pnlTemplateEdit.btnSaveTemplate then
        function dialog.pnlTemplateEdit.btnSaveTemplate:onChange() handleTemplateSave(dialog) end
    end

    if dialog.pnlTemplateEdit.btnWebhookAdd then
        function dialog.pnlTemplateEdit.btnWebhookAdd:onChange() handleWebhookAdd(dialog) end
    end

    if dialog.pnlTemplateEdit.btnWebhookEdit then
        function dialog.pnlTemplateEdit.btnWebhookEdit:onChange() handleWebhookEdit(dialog) end
    end

    if dialog.pnlTemplateEdit.btnWebhookDel then
        function dialog.pnlTemplateEdit.btnWebhookDel:onChange() handleWebhookDelete(dialog) end
    end

    -- Webhook edit controls
    if dialog.pnlWebhookEdit.btnWebhookCancel then
        function dialog.pnlWebhookEdit.btnWebhookCancel:onChange() handleWebhookCancel(dialog) end
    end

    if dialog.pnlWebhookEdit.btnWebhookSave then
        function dialog.pnlWebhookEdit.btnWebhookSave:onChange() handleWebhookSave(dialog) end
    end

    -- Initialize lists
    
    ResetWebhookListCombo(dialog)
    ResetTemplateListCombo(dialog)
    
    -- dialog.cmbTemplate:clear()
    -- local first = true
    -- for k,v in pairs(Webhooker.Server.templates) do
    --     local item = ListBoxItem.new(_(k))
    --     item.type = "any"
    --     dialog.cmbTemplate:insertItem(item)
    --     if first then dialog.cmbTemplate:selectItem(item) end
    --     first = false
    --     dialog.edtBody:setText(item:getText()) -- TODO
    -- end 

    --[[str = Webhooker.Server.templates["example2"].bodyRaw end
    dialog.edtBody:setText(str)]]

    --[[if dialog.webhookEditDialog.testButton then
        function dialog.webhookEditDialog.testButton:onChange()
            dialog.webhookEditDialog.testText:setText("Pressed")
            
        end
    end]]
end

--------------------------------------------------------------------------------------
-- RETURN
--------------------------------------------------------------------------------------
return {
    callbackOnShowDialog  = showDialog,

}