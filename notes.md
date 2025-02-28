management contract:
	flashloan USDC
		swap for PT
		deposit silo PT
		PT.afterDeposit callback manager.afterDeposit()
			manager.afterDeposit()
				Flashloan()
				transferFrom(alice)
				deposit into USDC vault
				call alice borrow PT
					PT.afterBorrow
						swap to USDC
						send to manager
				manager.close flashloan
		manager.afterCollateralize()
			bob usdc.borrow(flashloan amount)
			send to manager
		repay flashloan 


Need Manager Flashloan receiver
    - swap for pt funciton
    - call silo dpeosit function
    - afterPTDeposit callback
    - deposit into USDC vault function
    - calls borrow PT function
    - afterPTBorrow callback
    - calls borrow USDC function (flashloan amount)
    - afterUSDCBorrow callback repay flashloan 

PT.afterDeposit hook
    - call manager.afterDeposit()
PT.afterborrow hook
    - swap to USDC 
    - send to manager
    - call manager.afterPTBorrow callback
USDC.afterBorrow hook
    - send funds to manager
    - call manager.afterUSDCBorrow callback