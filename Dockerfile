# Stage 1: builder
FROM elixir:1.18-otp-27-alpine AS builder

ARG RELEASE_NAME
ENV MIX_ENV=prod
RUN apk update && apk upgrade
WORKDIR /app

# Copy mix files and config to leverage caching
COPY mix.exs mix.lock ./
COPY config/ config/

# Install Hex and Rebar and compile dependencies
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get && mix deps.compile

# Copy the rest of the files
#COPY . .
COPY ./config ./config
COPY ./lib ./lib
COPY ./rel ./rel
COPY ./test ./test
COPY ./LICENSE ./LICENSE
COPY ./README.md ./README.md

# Compile the project and generate the release
RUN mix compile
RUN mix release ${RELEASE_NAME}


# Stage 2: runtime
FROM alpine:latest

ARG RELEASE_NAME
ENV MIX_ENV=prod
WORKDIR /app

# Update the system
RUN apk update && apk upgrade
RUN apk update && apk add openssl ncurses-libs libgcc libstdc++

# setup the user
RUN addgroup -S extracker
RUN adduser -S extracker -G extracker

# create a volume for the backups
RUN mkdir /backups
VOLUME /backups

# create a volume for the config files (white/blacklists, etc)
RUN mkdir /config
VOLUME /config

# copy the built release from the builder stage
COPY --from=builder /app/_build/prod/rel/${RELEASE_NAME} ./

# set permissions once all files are in place
RUN chown -R extracker:extracker /app
RUN chown -R extracker:extracker /backups
RUN chown -R extracker:extracker /config

# Expose the default ports
EXPOSE 6969/tcp
EXPOSE 6969/udp
EXPOSE 7070/tcp

# set the non-root user
USER extracker

# build args are not available on runtime
ENV EXTRACKER_RELEASE_NAME=${RELEASE_NAME}

# Run the release
RUN chmod +x ./bin/${RELEASE_NAME}
CMD ["sh", "-c", "bin/${EXTRACKER_RELEASE_NAME} start"]
