import asyncio
import os
from playwright.async_api import async_playwright

async def get_page_structure():
    # 从环境变量读取浏览器类型，默认为chromium
    browser_type = os.getenv("BROWSER_TYPE", "chromium").lower()
    
    async with async_playwright() as p:
        if browser_type == "chromium":
            browser = await p.chromium.launch(headless=True)
            print(f"使用浏览器: Chromium")
        elif browser_type == "webkit":
            browser = await p.webkit.launch(headless=True)
            print(f"使用浏览器: WebKit")
        else:  # firefox or default
            browser = await p.firefox.launch(headless=True)
            print(f"使用浏览器: Firefox")
        
        page = await browser.new_page()

        try:
            print("访问登录页面...")
            # 访问登录页面
            await page.goto('https://test-aicc.airudder.com', timeout=30000)
            await page.wait_for_load_state('networkidle', timeout=30000)

            # 获取页面HTML结构
            content = await page.content()
            print('登录页面HTML结构:')
            print(content[:5000])  # 打印更多内容

            # 查找可能的输入框和按钮
            inputs = await page.query_selector_all('input')
            buttons = await page.query_selector_all('button')

            print(f"\n找到 {len(inputs)} 个输入框:")
            for i, inp in enumerate(inputs):
                name = await inp.get_attribute('name')
                type_attr = await inp.get_attribute('type')
                placeholder = await inp.get_attribute('placeholder')
                id_attr = await inp.get_attribute('id')
                print(f"  {i+1}. name='{name}', type='{type_attr}', placeholder='{placeholder}', id='{id_attr}'")

            print(f"\n找到 {len(buttons)} 个按钮:")
            for i, btn in enumerate(buttons):
                text = await btn.inner_text()
                type_attr = await btn.get_attribute('type')
                id_attr = await btn.get_attribute('id')
                class_attr = await btn.get_attribute('class')
                print(f"  {i+1}. text='{text}', type='{type_attr}', id='{id_attr}', class='{class_attr}'")

        except Exception as e:
            print(f'错误: {e}')
            import traceback
            traceback.print_exc()

        await browser.close()

if __name__ == "__main__":
    asyncio.run(get_page_structure())