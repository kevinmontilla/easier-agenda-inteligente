# 📅 Easier - Agenda Escolar Inteligente

**Easier** es una solución integral para la gestión académica que combina una aplicación móvil moderna con potentes automatizaciones de backend. Diseñada para estudiantes que buscan optimizar su tiempo, centraliza horarios, tareas y recordatorios en un solo lugar, con sincronización inteligente de datos.

![Easier App Banner](screenshots/logotipo_color.png)

## 🚀 Características Principales

### 📱 Aplicación Móvil (Flutter)
- **Multiplataforma:** Disponible para Android e iOS.
- **Gestión de Horarios:** Visualización clara de clases y materias.
- **Seguimiento de Tareas:** Lista de pendientes con estados (Pendiente, En Progreso, Completado).
- **Interfaz Intuitiva:** Diseño limpio y moderno enfocado en la experiencia de usuario (UX).

### ⚡ Automatización (n8n)
- **Sincronización Inteligente:** Flujos de trabajo en **n8n** que conectan la app con servicios externos (Bases de Datos).
- **Gestión de Datos:** Procesamiento de información en segundo plano sin cargar el dispositivo móvil.

## 🛠️ Stack Tecnológico

Este proyecto utiliza una arquitectura híbrida:

* **Frontend:** ![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white) ![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
* **Automatización / Backend:** ![n8n](https://img.shields.io/badge/n8n-%23FF6584.svg?style=for-the-badge&logo=n8n&logoColor=white)
* **Plataformas Nativas:** Soporte mediante C++ (Android/Linux) y Swift (iOS).

## 📂 Estructura del Proyecto

```text
easier-agenda-inteligente/
├── app/                 # Código fuente de la aplicación Flutter (Dart)
│   ├── lib/             # Lógica de la interfaz y modelos
│   ├── android/         # Configuración nativa Android
│   └── ios/             # Configuración nativa iOS
├── n8n/
│   └── workflows/       # Archivos .json con los flujos de automatización
├── screenshots/         # Imágenes demostrativas de la aplicación
└── README.md            # Documentación
```

## ⚙️ Instalación y Despliegue
1. Aplicación Móvil (Flutter)
   
Para ejecutar la aplicación en tu entorno local:

```text
Bash

# Navegar a la carpeta de la app
cd app

# Instalar dependencias
flutter pub get

# Ejecutar en un emulador o dispositivo conectado
flutter run
```

2. Flujos de Automatización (n8n)
   
La lógica del servidor reside en los flujos de n8n:

• Tener una instancia de n8n corriendo (Local o Cloud).

• Ir a la carpeta n8n/workflows de este repositorio.

• Importar los archivos .json en tu panel de n8n.

• Configurar las credenciales (API Keys, Webhooks) según sea necesario.

## Screenshots

<div align="center">
  <img src="screenshots/pantalla_inicial.jpg" alt="Pantalla de Inicio" width="250"/>
  <img src="screenshots/interfaz_inicio.jpg" alt="Interfaz de Inicio" width="250"/>
  <img src="screenshots/calendario.jpg" alt="Calendario" width="250"/>
</div>
<div align="center">
  <img src="screenshots/seccion_materias.jpg" alt="Materias" width="250"/>
  <img src="screenshots/premium.jpg" alt="Premium" width="250"/>
  <img src="screenshots/perfil.jpg" alt="Perfil" width="250"/>
</div>

<br>

## Video Demostrativo


<div align="center">
  <img src="screenshots/demostración_easier.gif" alt="Demostracion" width="250"/>
</div>

<br>

📅 Estado del Proyecto
Versión: 1.0 (Beta)

Estado: 🟡 En desarrollo.
