# Limpar memória da sessão do RStudio, com as variáveis
# rm(list = ls())
# .rs.restartR()

library('tidyverse')
library('tidylog')
library('data.table')

# Variável principal - modificar cada vez que for rodar, por lote e ano
ano <- '2022'

# Pastas de arquivos
# pasta_origem   <- '/home/livre/Desktop/Base_GtsRegionais/GitLab/api_radares_dados/tmp_brutos_radares/tmp_radares6'
pasta_origem  <- '/media/livre/Expansion/Radar/PROCREV'
pasta_volume  <- sprintf('%s/02_VOLUME', pasta_origem)
pasta_graficos <- sprintf('%s/04_VOLGRA/VOL_%s', pasta_origem, ano)
dir.create(pasta_graficos, recursive = TRUE, showWarnings = TRUE)

# Listar arquivos a serem processados
f_pattern <- sprintf('^VOL_L[1-4]_%s[0-9]{4}.csv', ano)
arquivos_volumes <-
  list.files(pasta_volume, pattern = f_pattern, recursive = TRUE, full.names = TRUE) %>%
  as.data.frame() %>%
  setNames('arqs')


# ------------------------------------------------------------------------------
# Agrupar volumetrias
# ------------------------------------------------------------------------------

agrupar_volumetrias <- function(df_arquivos, string_pattern) {
  # df_arquivos <- arquivos_volumes; string_pattern <- sprintf('VOL_L2_%s', ano)

  # Filtrar segmento de interesse (por lote) para processamento em paralelo
  volumes <- df_arquivos %>% filter(str_detect(arqs, string_pattern))


  # Juntar todos os arquivos de volumetria em um único dataframe
  volumes <-
    lapply(X = volumes, FUN = read_delim, delim = ';', col_types = 'cci') %>%
    rbindlist(fill = TRUE)

  # Agrupar resultados por dia e local
  volumes <-
    volumes %>%
    # Coluna 0000 sempre será um erro de registro
    filter(str_detect(local, '[0-9]{4}') & local != '0000') %>%
    group_by(data, local) %>%
    summarise(total = sum(n)) %>%
    ungroup() %>%
    pivot_wider(id_cols = data, names_from = local, values_from = total)

}

# Agrupar volumetrias por lote
volumes_L1 <- agrupar_volumetrias(arquivos_volumes, sprintf('VOL_L1_%s', ano))
volumes_L2 <- agrupar_volumetrias(arquivos_volumes, sprintf('VOL_L2_%s', ano))
volumes_L3 <- agrupar_volumetrias(arquivos_volumes, sprintf('VOL_L3_%s', ano))
volumes_L4 <- agrupar_volumetrias(arquivos_volumes, sprintf('VOL_L4_%s', ano))

# Juntar todas as volumetrias
volumes_out <-
  volumes_L1 %>%
  full_join(volumes_L2, by = 'data') %>%
  full_join(volumes_L3, by = 'data') %>%
  full_join(volumes_L4, by = 'data')


# Alguns códigos de local estão vindo repetidos de lotes diferentes, provavelmente
# por erros nos registros. Exemplos são cod_local 0001, 0002 e 2443
cods_repetidos <- data.frame(cod_local = names(volumes_out)) %>% filter(str_detect(cod_local, 'x'))
cods_repetidos <- cods_repetidos %>% mutate(cod_local = str_replace(cod_local, '.x', '')) %>% arrange(cod_local)

# Códigos repetidos podem ser um erro na base, pois um código de local não deveria
# se repetir por lotes diferentes. Para os volumes, vamos assumir que o lote com
# maior quantidade de dias com registros é o que traz os dados corretos - são
# estes os que serão considerados nos volumes e gráficos. Ainda assim, vamos
# registrar quais são os códigos que apareceram como repetidos para averiguação
out_cods_rep <- sprintf('%s/VOL_%s_CODS_ENTRE_LOTES.csv', pasta_volume, ano)
write_delim(cods_repetidos, out_cods_rep, delim = ';')


# Para cada um desses códigos, descartar coluna com menos ocorrências
if (nrow(cods_repetidos) > 0) {

  for (cod in cods_repetidos$cod_local) {
    # cod <- cods_repetidos$cod_local[1]
    print(cod)

    # Inserir .x e .y no número base do código local: 0099.x e 0099.y
    cod1 <- sprintf('%s.x', cod); cod2 <- sprintf('%s.y', cod);


    # # Pode ser que haja três colunas: 0000, 0000.x e 0000.y. Se for este o caso:
    # if (base_cod %in% names(volumes_out)) {
    #   # De cada uma das colunas, puxar o valor numérico. Caso ele exista nas
    #   # duas colunas, somá-los
    #   cod_agreg <-
    #     volumes_out %>%
    #     select(data, base_cod, cod, cod2) %>%
    #     # Renomear colunas de código repetidas, para facilitar o processamento
    #     setNames(c('data', 'w', 'x', 'y')) %>%
    #     filter(!is.na(w) | !is.na(x) | !is.na(y)) %>%
    #     # sample_n(20) %>%
    #     mutate(across(where(is.numeric), ~replace_na(.x, 0)),
    #            z = w + x + y) %>%
    #     # Descartar colunas originais, mantendo só data e resultado
    #     select(-c(w, x, y))
    #
    #   # Renomear colunas para reestabelecer código original
    #   names(cod_agreg) <- c('data', base_cod)
    #
    #   # Substituir colunas .x e .y no df original pela dos resultados agregados
    #   volumes_out <-
    #     volumes_out %>%
    #     select(-c(base_cod, cod, cod2)) %>%
    #     left_join(cod_agreg, by = 'data')
    #
    #
    #   # Se houver somente as colunas 0000.y e 0000.x:
    # } else {
    #   # De cada uma das colunas, puxar o valor numérico. Caso ele exista nas
    #   # duas colunas, somá-los
    #   cod_agreg <-
    #     volumes_out %>%
    #     select(data, cod, cod2) %>%
    #     # Renomear colunas de código repetidas, para facilitar o processamento
    #     setNames(c('data', 'x', 'y')) %>%
    #     filter(!is.na(x) | !is.na(y)) %>%
    #     # sample_n(20) %>%
    #     mutate(across(where(is.numeric), ~replace_na(.x, 0)),
    #            z = x + y) %>%
    #     # Descartar colunas originais, mantendo só data e resultado
    #     select(-c(x, y))
    #
    #   # Renomear colunas para reestabelecer código original
    #   names(cod_agreg) <- c('data', base_cod)
    #
    #   # Substituir colunas .x e .y no df original pela dos resultados agregados
    #   volumes_out <-
    #     volumes_out %>%
    #     select(-c(cod, cod2)) %>%
    #     left_join(cod_agreg, by = 'data')
    #
    # }

    # Comparar quantas vezes aquele código aparece em cada coluna
    comparativo1 <- volumes_out %>% select(all_of(cod1))  %>% distinct() %>% nrow()
    comparativo2 <- volumes_out %>% select(all_of(cod2)) %>% distinct() %>% nrow()
    print(sprintf('Ocorrências: %i vs %i', comparativo1, comparativo2))

    # Descartar coluna com menos ocorrência
    if (comparativo1 > comparativo2) {
      volumes_out <- volumes_out %>% select(-all_of(cod2))

    } else if (comparativo2 > comparativo1) {
      volumes_out <- volumes_out %>% select(-all_of(cod1))

    } else {
      # Se as duas colunas têm a mesma quantidade, ambas são um erro, tanto faz
      volumes_out <- volumes_out %>% select(-all_of(cod1))

    }

  }

  # Renomear coluna que fica para cod_local sem .x ou .y
  names(volumes_out) <- str_replace(names(volumes_out), '.[xy]', '')
}


# Gravar resultados
out_file <- sprintf('%s/VOL_%s.csv', pasta_volume, ano)
write_delim(volumes_out, out_file, delim = ';')


# ------------------------------------------------------------------------------
# Dados sobre dias sem registro e volumes repetidos (prováveis erros)
# ------------------------------------------------------------------------------

# Remover anos não relacionados a este
volumes_out <- volumes_out %>% filter(str_starts(data, ano))

# sum(volumes_out$`6690`)

# Quantos dias cada local ficou sem registro?
dias_sem_registro <-
  # Somar quantidade de NAs em cada coluna
  colSums(is.na(volumes_out)) %>%
  # Transformar de volta em dataframe
  as.data.frame() %>%
  # Pegar a primeira linha e usar como nomes de colunas, depois descartá-la
  setNames(slice(., 1)) %>%
  slice(2:nrow(.)) %>%
  # Inserir um nome para a primeira coluna (que havia ficado como um .index)
  rownames_to_column(var = 'X1') %>%
  # Nomear as colunas direito
  setNames(c('local', 'dias_sem_registro'))


# Quantos valores únicos cada local registrou? Número deve estar o mais próximo
# possível da quantidade de dias do ano (365, 366)
# https://stackoverflow.com/questions/22196078/count-unique-values-for-every-column
valores_unicos <-
  volumes_out %>%
  # Quantidade de valores únicos
  summarise_all(n_distinct) %>%
  t() %>%
  # Transformar de volta em dataframe
  as.data.frame() %>%
  # Pegar a primeira linha e usar como nomes de colunas, depois descartá-la
  setNames(slice(., 1)) %>%
  slice(2:nrow(.)) %>%
  # Inserir um nome para a primeira coluna (que havia ficado como um .index)
  rownames_to_column(var = 'X1') %>%
  # Nomear as colunas direito
  setNames(c('local', 'volumes_unicos'))


# Puxar valor de volume que mais se repete para cada local, desde que se repita
# mais de 5 vezes - o que sugere algum erro na base
valores_repetidos <-
  volumes_out %>%
  # Transformar colunas de locais em linhas
  pivot_longer(cols = names(volumes_out)[2:length(volumes_out)],
               names_to = 'local',
               values_to = 'volume') %>%
  # Remover linhas vazias
  filter(!is.na(volume)) %>%
  # group_by(local) %>%
  # summarise(n = sum(volume)) %>%
  # filter(local == '6690')
  # Puxar o valor que mais se repete, desde que se repita mais de 5 vezes
  group_by(local, volume) %>%
  tally() %>%
  filter(n == max(n) & n > 5) %>%
  rename(volume_repetido = volume, qtd_repeticoes = n)


# Juntar dados gerais de dias vazios e volumes repetidos
resumo_locais <-
  dias_sem_registro %>%
  full_join(valores_unicos, by = 'local') %>%
  full_join(valores_repetidos, by = 'local') %>%
  # Valores repetidos
  mutate(volumes_repetidos = 365 - volumes_unicos - dias_sem_registro, .after = 'volumes_unicos')


# Gravar resultados
out_file2 <- sprintf('%s/VOL_%s_RESUMO.csv', pasta_volume, ano)
write_delim(resumo_locais, out_file2, delim = ';')

# head(volumes_out)
# names(volumes_out)

# volumes_L1 %>% select(data, `6602`) %>% filter(`6602` == 360)

# ------------------------------------------------------------------------------
# Criar gráficos para cada local
# ------------------------------------------------------------------------------

# Remover colunas em que os códigos aparecem mas são somente NA
# https://stackoverflow.com/questions/15968494/how-to-delete-columns-that-contain-only-nas
volumes_out <- volumes_out %>% select(where(~!all(is.na(.x))))

# Selecionar todos os locais a partir dos nomes das colunas
locais <- volumes_out %>% select(-data) %>% names()


# Gerar um gráfico de volume registrado por dia para cada local
for (local in locais) {

  png(filename = sprintf('%s/VOL_%s_%s.png', pasta_graficos, local, ano))

  volumes_out %>%
    add_column(index = 1:nrow(.), .after = 'data') %>%
    select(index, all_of(local)) %>%
    plot(main = sprintf('Volumetria: Local %s // Ano %s', local, ano),
         xlab = 'dias do ano',
         ylab = 'volume',
         cex = 0.25,
         cex.axis = 0.8,
         las = 1)

  dev.off()
}
