return {
    useOxInventory = true,
    imagePath = 'nui://ox_inventory/web/images/%s.png',
    defaultCurrency = 'money',
    currencyLabels = {
        money = 'Cash',
        black_money = 'Dirty Money',
    },

    --- Store manager — all shops are created in-city via this panel
    manager = {
        command = 'shopmanager',
        groupPermission = 'group.admin', -- Qbox ACE for admins
        acePermission = 'w-shops.manage', -- optional ace fallback
        allowAll = true, -- dev: allow any player; set false on live server
    },
}
