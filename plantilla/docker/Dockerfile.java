# Base Java 21 (Temurin) — MS2 (Spring Boot + PostgreSQL). Multi-stage: build con Maven, runtime jre.
# Copiar a tu repo como `Dockerfile`. Tuning para t3.small (ver MS2-10 y riesgo R7).

# --- build ---
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline
COPY src ./src
RUN mvn -q -DskipTests package

# --- runtime ---
FROM eclipse-temurin:21-jre-jammy
ENV PORT=8002 \
    JAVA_OPTS="-Xmx256m -XX:MaxRAMPercentage=75 -XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError"
WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m app

COPY --from=build /src/target/*.jar app.jar
USER app

EXPOSE 8002

# Spring Boot Actuator expone /actuator/health
HEALTHCHECK --interval=15s --timeout=3s --start-period=45s --retries=3 \
  CMD curl -fsS "http://localhost:${PORT}/actuator/health" || exit 1

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar --server.port=${PORT}"]
