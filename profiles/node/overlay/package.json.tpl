{
  "name": "{{PRODUCT_NAME}}",
  "version": "0.1.0",
  "private": true,
  "description": "{{DISPLAY_NAME}}",
  "type": "module",
  "engines": {
    "node": ">=20"
  },
  "scripts": {
    "check": "node --check src/index.js",
    "test": "node --test",
    "verify": "npm run check && npm test"
  }
}
